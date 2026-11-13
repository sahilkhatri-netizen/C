// video-progress: records how much of the two funnel videos a lead watched (13 Nov 2026, Aakash/Sahil):
//   power-funnel    = Power Funnel video on the home page dfy.independentonlinecoach.com/ (before applying, ~29 min)
//   offer-breakdown = Offer Breakdown video on /call-scheduled-dfy (after booking, ~34 min)
// Both autoplay muted; the page script only counts seconds played with sound on.
//
// Called by the small script in the DFY funnel footer (see ../page-script.html)
// every time the viewer passes another 5% of the video (with sound on — muted autoplay is not counted). Public endpoint (the browser calls it), so it:
//   - only accepts the known video ids,
//   - only ever RAISES the stored %, never lowers it,
//   - only touches an existing GHL contact found by id, email or phone (never creates one),
//   - only adds a tag and sets one number field — never messages the lead.
//
// What it writes:
//   Supabase public.video_watch      — one row per contact + video: max %, seconds watched, first/last time
//   Supabase public.video_watch_events — every ping (debugging)
//   GHL contact field "Offer Video Watched %" (kg0uyvqWv6f8ZVv2sWDk) / "Power Funnel Video Watched %" (gFhpd2M26IkaKdUmgEYk)
//   GHL tags offer-video-25/-50/-75/-100 or power-funnel-video-25/... when first passed (100 = 95%+)
//
// Body (JSON, sent as text/plain so the browser skips the CORS preflight):
//   { media, pct, watched, duration, page, ident: { contact_id?, email?, phone? } }
import { createClient } from "npm:@supabase/supabase-js@2";

// media id -> GHL field + tag prefix. "0quz6oc5jo" = a hidden Wistia copy of the offer video, kept in case it is switched on.
const MEDIA: Record<string, { field: string; tag: string }> = {
  "offer-breakdown": { field: "kg0uyvqWv6f8ZVv2sWDk", tag: "offer-video" },
  "0quz6oc5jo": { field: "kg0uyvqWv6f8ZVv2sWDk", tag: "offer-video" },
  "power-funnel": { field: "gFhpd2M26IkaKdUmgEYk", tag: "power-funnel-video" },
};
const LOCATION = "LZkgKOxmYpiZl17MKuno";
const API = "https://services.leadconnectorhq.com";
const MILESTONES = [25, 50, 75, 100];

function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); return k.default ?? Object.values(k)[0] as string; } catch { return ""; }
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), { auth: { persistSession: false } });
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const clean = (v?: string | null) => (v ? v.trim().replace(/^["'<\s]+|["'>\s]+$/g, "") : null);

async function token() {
  const { data } = await db.rpc("ghl_sync_secrets");
  const v = (Array.isArray(data) ? data[0] : data) ?? {};
  return clean(Deno.env.get("ghl_api_token") || Deno.env.get("GHL_API_TOKEN") || v.api_token);
}
async function ghl(tok: string, method: string, path: string, body?: unknown) {
  for (let i = 0; i < 3; i++) {
    const r = await fetch(API + path, {
      method,
      headers: { Authorization: `Bearer ${tok}`, Version: "2021-07-28", Accept: "application/json", "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (r.status === 429) { await new Promise((s) => setTimeout(s, 1200 * (i + 1))); continue; }
    const t = await r.text();
    let j: any = {}; try { j = JSON.parse(t); } catch { /* not json */ }
    return { ok: r.ok, status: r.status, j, t };
  }
  return { ok: false, status: 429, j: {}, t: "rate limited" };
}

// Which GHL contact is watching? contact id first (checked against email if both given), then email, then phone.
async function resolve(tok: string, ident: any): Promise<{ id: string; by: string } | null> {
  const id = String(ident?.contact_id ?? "").trim();
  const email = String(ident?.email ?? "").trim().toLowerCase();
  const phone = String(ident?.phone ?? "").replace(/[^\d+]/g, "");
  if (/^[A-Za-z0-9]{15,30}$/.test(id)) {
    const r = await ghl(tok, "GET", `/contacts/${id}`);
    const c = r.j?.contact;
    if (r.ok && c?.id && c.locationId === LOCATION) {
      if (!email || !c.email || String(c.email).toLowerCase() === email) return { id: c.id, by: "contact_id" };
    }
  }
  if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    const r = await ghl(tok, "GET", `/contacts/search/duplicate?locationId=${LOCATION}&email=${encodeURIComponent(email)}`);
    if (r.ok && r.j?.contact?.id) return { id: r.j.contact.id, by: "email" };
  }
  const digits = phone.replace(/\D/g, "");
  if (digits.length >= 10) {
    const e164 = phone.startsWith("+") ? phone : digits.length === 10 ? `+91${digits}` : `+${digits}`;
    const r = await ghl(tok, "GET", `/contacts/search/duplicate?locationId=${LOCATION}&number=${encodeURIComponent(e164)}`);
    if (r.ok && r.j?.contact?.id) return { id: r.j.contact.id, by: "phone" };
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ ok: true, info: "video-progress is up" });
  let p: any = {};
  try { p = JSON.parse(await req.text()); } catch { return json({ ok: false, error: "bad json" }, 400); }

  const media = String(p.media ?? "");
  const pct = Math.max(0, Math.min(100, Math.round(Number(p.pct) || 0)));
  const watched = Math.max(0, Math.round(Number(p.watched) || 0));
  const duration = Math.max(0, Math.round(Number(p.duration) || 0)) || null;
  const page = String(p.page ?? "").slice(0, 300) || null;
  const ua = (req.headers.get("user-agent") ?? "").slice(0, 300);
  const ident = { contact_id: p.ident?.contact_id ?? null, email: p.ident?.email ?? null, phone: p.ident?.phone ?? null };
  const log = (contact_id: string | null, matched_by: string | null, result: string) =>
    db.from("video_watch_events").insert({ contact_id, media_id: media, pct, watched_sec: watched, duration_sec: duration, matched_by, ident, page, ua, result }).then(() => {}, () => {});

  const M = MEDIA[media];
  if (!M) { await log(null, null, "unknown media"); return json({ ok: false, error: "unknown media" }, 400); }
  if (pct < 1) return json({ ok: true, skipped: "nothing watched yet" });
  if (!ident.contact_id && !ident.email && !ident.phone) { await log(null, null, "no ident"); return json({ ok: false, error: "no contact info" }); }

  const tok = await token();
  if (!tok) { await log(null, null, "ghl token missing"); return json({ ok: false, error: "server not ready" }, 503); }
  const who = await resolve(tok, ident);
  if (!who) { await log(null, null, "contact not found"); return json({ ok: false, error: "contact not found" }); }

  const { data: prev } = await db.from("video_watch").select("max_pct, ghl_tags, plays, watched_sec").eq("contact_id", who.id).eq("media_id", media).maybeSingle();
  const oldPct = prev?.max_pct ?? 0;
  const newPct = Math.max(oldPct, pct);
  const reached = MILESTONES.filter((m) => (m === 100 ? newPct >= 95 : newPct >= m));
  const have = new Set<string>(prev?.ghl_tags ?? []);
  const newTags = reached.map((m) => `${M.tag}-${m}`).filter((t) => !have.has(t));

  const now = new Date().toISOString();
  await db.from("video_watch").upsert({
    contact_id: who.id, media_id: media, max_pct: newPct,
    watched_sec: Math.max(prev?.watched_sec ?? 0, watched), duration_sec: duration,
    plays: prev ? prev.plays + (p.start ? 1 : 0) : 1,
    last_at: now, page, matched_by: who.by, ghl_tags: [...have, ...newTags],
    ...(prev ? {} : { first_at: now }),
  }, { onConflict: "contact_id,media_id" });

  // GHL: number field whenever the max goes up by 5+ points (or a milestone is crossed); tags once per milestone
  const errors: string[] = [];
  if (newPct >= oldPct + 5 || newTags.length || (!prev && newPct > 0)) {
    const r = await ghl(tok, "PUT", `/contacts/${who.id}`, { customFields: [{ id: M.field, field_value: newPct }] });
    if (!r.ok) errors.push(`field ${r.status}: ${r.t.slice(0, 160)}`);
  }
  if (newTags.length) {
    const r = await ghl(tok, "POST", `/contacts/${who.id}/tags`, { tags: newTags });
    if (!r.ok) errors.push(`tags ${r.status}: ${r.t.slice(0, 160)}`);
  }
  await log(who.id, who.by, errors.length ? "saved; ghl error: " + errors.join(" | ") : `saved ${oldPct}->${newPct}${newTags.length ? " +" + newTags.join(",") : ""}`);
  return json({ ok: true, pct: newPct, tags: newTags });
});
