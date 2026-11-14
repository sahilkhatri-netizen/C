import { createClient } from "npm:@supabase/supabase-js@2";
// media id -> GHL field + tag prefix. "0quz6oc5jo" = a hidden Wistia copy of the offer video, kept in case it is switched on.
const MEDIA = {
  "offer-breakdown": {
    field: "kg0uyvqWv6f8ZVv2sWDk",
    tag: "offer-video"
  },
  "0quz6oc5jo": {
    field: "kg0uyvqWv6f8ZVv2sWDk",
    tag: "offer-video"
  },
  "power-funnel": {
    field: "gFhpd2M26IkaKdUmgEYk",
    tag: "power-funnel-video"
  },
  // every other clip on the funnel pages (testimonials). No GHL number field; one tag once a clip is watched.
  "testimonials": {
    field: null,
    tag: "testimonials"
  }
};
// Main videos are ~30 min. A report shorter than this is a testimonial clip an old page script mistook for the main video.
const MIN_MAIN_SEC = 300;
const LOCATION = "LZkgKOxmYpiZl17MKuno";
const API = "https://services.leadconnectorhq.com";
const MILESTONES = [
  25,
  50,
  75,
  100
];
function serviceKey() {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try {
    const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return k.default ?? Object.values(k)[0];
  } catch  {
    return "";
  }
}
const db = createClient(Deno.env.get("SUPABASE_URL"), serviceKey(), {
  auth: {
    persistSession: false
  }
});
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type"
};
const json = (b, s = 200)=>new Response(JSON.stringify(b), {
    status: s,
    headers: {
      ...CORS,
      "Content-Type": "application/json"
    }
  });
const clean = (v)=>v ? v.trim().replace(/^["'<\s]+|["'>\s]+$/g, "") : null;
// ---- GHL token: "ioc" app token first, private API key as backup (Nov 13 2026) ----
// rpc ghl_token hands out the app's OAuth token (kept fresh by edge function ghl-token-refresh) and counts the use in
// ghl_token_use. If the app token is missing/expired, or GHL refuses it (401/403), the same call is retried with the
// API key and that is logged (rpc ghl_token_fallback) — nothing breaks, and the log shows what still needs the key.
// A refused call was not carried out by GHL, so retrying it (also a write) is safe.
const GHL_CALLER = "video-progress";
let GHL_KEY = null;
let GHL_PICK = null;
const ghlCleanTok = (v)=>(v ? String(v).trim().replace(/^["'<\s]+|["'>\s]+$/g, "") : null) || null;
async function ghlPick(fresh = false) {
  if (!fresh && GHL_PICK && Date.now() - GHL_PICK.at < 5 * 60e3) return GHL_PICK.tok;
  const envKey = ghlCleanTok(Deno.env.get("ghl_api_token") || Deno.env.get("GHL_API_TOKEN"));
  GHL_KEY = envKey || GHL_KEY;
  let tok = null;
  try {
    const v = await (async ()=>{
      const { data, error } = await db.rpc("ghl_token", {
        p_caller: GHL_CALLER
      });
      if (error) throw new Error(error.message);
      return Array.isArray(data) ? data[0] : data;
    })();
    GHL_KEY = envKey || ghlCleanTok(v?.key) || GHL_KEY;
    if (v?.app) tok = String(v.app);
  } catch (e) {
    console.error("ghl_token pick failed, using API key", e);
  }
  tok = tok || GHL_KEY;
  GHL_PICK = {
    at: Date.now(),
    tok
  };
  return tok;
}
async function ghlFetch(url, token, init) {
  const go = (t)=>fetch(url, {
      ...init,
      headers: {
        ...init.headers,
        Authorization: `Bearer ${t}`
      }
    });
  let r = await go(token);
  if ((r.status === 401 || r.status === 403) && token !== GHL_KEY) {
    await r.text().catch(()=>"");
    if (r.status === 401) {
      const now = await ghlPick(true);
      if (now && now !== token && now !== GHL_KEY) {
        r = await go(now);
        if (r.status !== 401 && r.status !== 403) return r;
        await r.text().catch(()=>"");
      }
    }
    if (!GHL_KEY) return go(token);
    GHL_PICK = null;
    const p_path = url.replace("https://services.leadconnectorhq.com", "");
    try {
      await db.rpc("ghl_token_fallback", {
        p_caller: GHL_CALLER,
        p_status: r.status,
        p_path
      });
    } catch  {}
    r = await go(GHL_KEY);
  }
  return r;
}
async function token() {
  return await ghlPick();
}
async function ghl(tok, method, path, body) {
  for(let i = 0; i < 3; i++){
    const r = await ghlFetch(API + path, tok, {
      method,
      headers: {
        Version: "2021-07-28",
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    if (r.status === 429) {
      await new Promise((s)=>setTimeout(s, 1200 * (i + 1)));
      continue;
    }
    const t = await r.text();
    let j = {};
    try {
      j = JSON.parse(t);
    } catch  {}
    return {
      ok: r.ok,
      status: r.status,
      j,
      t
    };
  }
  return {
    ok: false,
    status: 429,
    j: {},
    t: "rate limited"
  };
}
// Which GHL contact is watching? contact id first (checked against email if both given), then email, then phone.
async function resolve(tok, ident) {
  const id = String(ident?.contact_id ?? "").trim();
  const email = String(ident?.email ?? "").trim().toLowerCase();
  const phone = String(ident?.phone ?? "").replace(/[^\d+]/g, "");
  if (/^[A-Za-z0-9]{15,30}$/.test(id)) {
    const r = await ghl(tok, "GET", `/contacts/${id}`);
    const c = r.j?.contact;
    if (r.ok && c?.id && c.locationId === LOCATION) {
      if (!email || !c.email || String(c.email).toLowerCase() === email) return {
        id: c.id,
        by: "contact_id"
      };
    }
  }
  if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    const r = await ghl(tok, "GET", `/contacts/search/duplicate?locationId=${LOCATION}&email=${encodeURIComponent(email)}`);
    if (r.ok && r.j?.contact?.id) return {
      id: r.j.contact.id,
      by: "email"
    };
  }
  const digits = phone.replace(/\D/g, "");
  if (digits.length >= 10) {
    const e164 = phone.startsWith("+") ? phone : digits.length === 10 ? `+91${digits}` : `+${digits}`;
    const r = await ghl(tok, "GET", `/contacts/search/duplicate?locationId=${LOCATION}&number=${encodeURIComponent(e164)}`);
    if (r.ok && r.j?.contact?.id) return {
      id: r.j.contact.id,
      by: "phone"
    };
  }
  return null;
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") return new Response(null, {
    status: 204,
    headers: CORS
  });
  if (req.method !== "POST") return json({
    ok: true,
    info: "video-progress is up"
  });
  let p = {};
  try {
    p = JSON.parse(await req.text());
  } catch  {
    return json({
      ok: false,
      error: "bad json"
    }, 400);
  }
  const media = String(p.media ?? "");
  const pct = Math.max(0, Math.min(100, Math.round(Number(p.pct) || 0)));
  const watched = Math.max(0, Math.round(Number(p.watched) || 0));
  const duration = Math.max(0, Math.round(Number(p.duration) || 0)) || null;
  const page = String(p.page ?? "").slice(0, 300) || null;
  const ua = (req.headers.get("user-agent") ?? "").slice(0, 300);
  const ident = {
    contact_id: p.ident?.contact_id ?? null,
    email: p.ident?.email ?? null,
    phone: p.ident?.phone ?? null
  };
  const log = (contact_id, matched_by, result, detail = null)=>db.from("video_watch_events").insert({
      contact_id,
      media_id: media,
      pct,
      watched_sec: watched,
      duration_sec: duration,
      matched_by,
      ident,
      page,
      ua,
      result,
      detail: detail ?? null
    }).then(()=>{}, ()=>{});
  const M = MEDIA[media];
  if (!M) {
    await log(null, null, "unknown media");
    return json({
      ok: false,
      error: "unknown media"
    }, 400);
  }
  const isT = media === "testimonials";
  if (!isT && duration && duration < MIN_MAIN_SEC) {
    await log(null, null, "ignored: short clip reported as main video");
    return json({
      ok: true,
      skipped: "short clip"
    });
  }
  if (!isT && pct < 1) return json({
    ok: true,
    skipped: "nothing watched yet"
  });
  if (isT && watched < 3) return json({
    ok: true,
    skipped: "nothing watched yet"
  });
  if (!ident.contact_id && !ident.email && !ident.phone) {
    await log(null, null, "no ident");
    return json({
      ok: false,
      error: "no contact info"
    });
  }
  const tok = await token();
  if (!tok) {
    await log(null, null, "ghl token missing");
    return json({
      ok: false,
      error: "server not ready"
    }, 503);
  }
  const who = await resolve(tok, ident);
  if (!who) {
    await log(null, null, "contact not found");
    return json({
      ok: false,
      error: "contact not found"
    });
  }
  if (isT) {
    const { data: pt } = await db.from("video_watch").select("detail, ghl_tags").eq("contact_id", who.id).eq("media_id", media).maybeSingle();
    const map = {};
    for (const c of pt?.detail?.clips ?? [])if (c?.k) map[c.k] = c;
    for (const c of Array.isArray(p.clips) ? p.clips.slice(0, 80) : []){
      const k = String(c?.k ?? "").slice(0, 80);
      if (!k) continue;
      const old = map[k];
      const d = Math.max(0, Math.round(Number(c.d) || 0)) || old?.d || 0;
      let w = Math.max(0, Math.round(Number(c.w) || 0));
      if (d) w = Math.min(w, d);
      map[k] = {
        k,
        n: String(c.n ?? old?.n ?? "").slice(0, 80),
        d,
        w: Math.max(old?.w ?? 0, w)
      };
    }
    const clips = Object.values(map).filter((c)=>c.w > 0);
    const total = Math.min(200, Math.max(Math.round(Number(p.total) || 0), pt?.detail?.total ?? 0, clips.length));
    const seen = clips.filter((c)=>c.d > 0 && c.w >= c.d * 0.5).length;
    const sec = clips.reduce((a, c)=>a + c.w, 0);
    const have = new Set(pt?.ghl_tags ?? []);
    const newTags = seen >= 1 && !have.has("testimonials-watched") ? [
      "testimonials-watched"
    ] : [];
    const detail = {
      total,
      clips
    };
    const now = new Date().toISOString();
    await db.from("video_watch").upsert({
      contact_id: who.id,
      media_id: media,
      max_pct: total ? Math.min(100, Math.round(seen * 100 / total)) : 0,
      watched_sec: sec,
      duration_sec: clips.reduce((a, c)=>a + c.d, 0) || null,
      plays: seen,
      last_at: now,
      page,
      matched_by: who.by,
      ghl_tags: [
        ...have,
        ...newTags
      ],
      detail,
      ...pt ? {} : {
        first_at: now
      }
    }, {
      onConflict: "contact_id,media_id"
    });
    let err = "";
    if (newTags.length) {
      const r = await ghl(tok, "POST", `/contacts/${who.id}/tags`, {
        tags: newTags
      });
      if (!r.ok) err = `; ghl error: tags ${r.status}: ${r.t.slice(0, 160)}`;
    }
    await log(who.id, who.by, `saved testimonials ${seen}/${total} watched, ${clips.length} started${newTags.length ? " +" + newTags.join(",") : ""}${err}`, detail);
    return json({
      ok: true,
      watched_clips: seen,
      total,
      tags: newTags
    });
  }
  const { data: prev } = await db.from("video_watch").select("max_pct, ghl_tags, plays, watched_sec").eq("contact_id", who.id).eq("media_id", media).maybeSingle();
  const oldPct = prev?.max_pct ?? 0;
  const newPct = Math.max(oldPct, pct);
  const reached = MILESTONES.filter((m)=>m === 100 ? newPct >= 95 : newPct >= m);
  const have = new Set(prev?.ghl_tags ?? []);
  const newTags = reached.map((m)=>`${M.tag}-${m}`).filter((t)=>!have.has(t));
  const now = new Date().toISOString();
  await db.from("video_watch").upsert({
    contact_id: who.id,
    media_id: media,
    max_pct: newPct,
    watched_sec: Math.max(prev?.watched_sec ?? 0, watched),
    duration_sec: duration,
    plays: prev ? prev.plays + (p.start ? 1 : 0) : 1,
    last_at: now,
    page,
    matched_by: who.by,
    ghl_tags: [
      ...have,
      ...newTags
    ],
    ...prev ? {} : {
      first_at: now
    }
  }, {
    onConflict: "contact_id,media_id"
  });
  // GHL: number field whenever the max goes up by 5+ points (or a milestone is crossed); tags once per milestone
  const errors = [];
  if (newPct >= oldPct + 5 || newTags.length || !prev && newPct > 0) {
    const r = await ghl(tok, "PUT", `/contacts/${who.id}`, {
      customFields: [
        {
          id: M.field,
          field_value: newPct
        }
      ]
    });
    if (!r.ok) errors.push(`field ${r.status}: ${r.t.slice(0, 160)}`);
  }
  if (newTags.length) {
    const r = await ghl(tok, "POST", `/contacts/${who.id}/tags`, {
      tags: newTags
    });
    if (!r.ok) errors.push(`tags ${r.status}: ${r.t.slice(0, 160)}`);
  }
  await log(who.id, who.by, errors.length ? "saved; ghl error: " + errors.join(" | ") : `saved ${oldPct}->${newPct}${newTags.length ? " +" + newTags.join(",") : ""}`);
  return json({
    ok: true,
    pct: newPct,
    tags: newTags
  });
});
