-- Note 1 new format (Closer Playbook triage script, agreed 5 Nov 2026) applied to the LIVE job.
-- Why: on 5 Nov the change went into routines/note1-lead-notes-prompt.txt on a side branch only.
-- The live Note 1 writer is Supabase ai_jobs.lead_notes (it replaced trig_014Tnqs86MGkRGayN83a9Bi8
-- on 11 Oct), whose instructions were last edited 29 Oct, so new bookings still got the old format.
-- Backup of the previous text: app_config key 'lead_notes_instructions_backup_20261107'.
-- Rollback: update ai_jobs set instructions = (select value from app_config where key =
--   'lead_notes_instructions_backup_20261107'), updated_at = now() where slug = 'lead_notes';
-- Note: ai_job_parts for lead_notes is an OLDER copy; do not run ai_job_assemble('lead_notes')
-- or it will overwrite this.
do $patch$
declare
  t text;
  r record;
  n int;
begin
  select instructions into t from ai_jobs where slug = 'lead_notes' for update;
  for r in select * from (values

-- 1. Offer video rule
(1, $o$7. OFFER VIDEO: watch tracking is NOT built yet — write no offer-video bullet and never say watched / not watched. Just make "Did you watch the Offer Breakdown video?" the first ASK THESE question (Note 1 only).$o$,
$n$7. OFFER VIDEO (updated 5 Nov 2026): the lead counts as WATCHED for the current booking only if the contact has a tag containing "video" or "watched" (e.g. "offer-video-75") added for this booking, OR has replied "WATCHED" or "READY" on WhatsApp/SMS since booking (check the conversation). Otherwise write the WEB RESEARCH bullet "**Offer video:** unknown for this booking — ask" and use the "not watched" branch of the TRIAGE SCRIPT Video line (Note 1). Never mark "not watched" from old data. Parts B and C: no offer-video bullet.$n$),

-- 2. Second-account use
(2, $o$use it in the Instagram score, the VERDICT reason and ASK THESE.$o$,
$n$use it in the Instagram score, the VERDICT reason and the TRIAGE SCRIPT (Note 1) or ASK THESE (Parts B and C).$n$),

-- 3. Investment score: payment plans are gone
(3, $o$  • Investment: 1 = <₹30k / "No - I can't invest" • 2 = ₹30–50k • 3 = ₹50k–1L / "Maybe if there's a payment plan" • 4 = ₹1–3L / "Yes - I can invest".$o$,
$n$  • Investment: 1 = <₹30k / "No - I can't invest" / "I'm not in a position to invest" • 2 = ₹30–50k / "I'll manage the funds if the opportunity is right" or no number • 3 = ₹50k–1L / "Maybe if there's a payment plan" (payment plans are no longer offered — max two parts — so the triage call must get a Yes to the ₹1L minimum) • 4 = ₹1–3L / "Yes - I can invest".$n$),

-- 4. Offer to pitch: new programs and prices
(4, $o$OFFER TO PITCH (Aakash's rule, Sep 25 2026 — never suggest Kickstarter)$o$,
$n$OFFER TO PITCH (Aakash's rule, updated 5 Nov 2026 from the Closer Playbook — never suggest Kickstarter, never a case study before the video)$n$),
(5, $o$≥₹2L → ₹6L Accelerator + ₹3L DFY • ₹50k–2L → ₹3L DFY • <₹50k or can't invest → DIH ₹1.77L on a payment plan. EXCEPTION: if the form, notes or past calls say they cannot or will not take sales calls themselves (time / founder-dependence / "sales was the issue"), pitch ₹3L DFY with the sales team built and trained by us — not DIH, which leaves them selling alone; say this in CALL IT.$o$,
$n$the three programs and their ONLY prices: Sales Jumpstart (DIH) ₹1L + GST = ₹1.18L • Sales Accelerator (DFY) ₹3L + GST = ₹3.54L • Sales Multiplier (DFY Scale) ₹6L + GST = ₹7.08L. Pick: <₹50k, B2C (not online yet) or can't invest ₹3L → Jumpstart ₹1.18L • ₹50k–2L → Accelerator ₹3.54L (the DEFAULT pitch) • ≥₹2L with proof, investment strong and sole decider → Multiplier ₹7.08L, and write "founder on the call before this pitch" (Aakash must join before any Multiplier pitch). EXCEPTION: if the form, notes or past calls say they cannot or will not take sales calls themselves (time / founder-dependence / "sales was the issue"), pitch the Accelerator with the sales team built and trained by us — not Jumpstart, which leaves them selling alone; say this in CALL IT. PAYMENT (every Note 1 CALL IT line ends with it): upfront first; at most two parts; NO payment plans; minimum ₹10k onboarding deposit on the call; the ALL IN upgrade is offered only if they clear the pending amount within 24 h. Stall fallback: the free community (7 Secrets to 7 Figures), never a discount, never a split beyond two parts.$n$),

-- 5. Writing limits
(6, $o$HISTORY (up to 5), WHY DISQUALIFIED (up to 5) and ASK THESE. Every bullet starts with a bold label, except ASK THESE (plain questions).$o$,
$n$HISTORY (up to 5), WHY DISQUALIFIED (up to 5), TRIAGE SCRIPT (up to 10, Note 1) and ASK THESE (Parts B and C). Every bullet starts with a bold label, except ASK THESE (plain questions).$n$),

-- 6. Slack mention for the new red-flag verdict
(7, $o$when the verdict is RECOVER (Part B) or TRIAGE (Part A)$o$,
$n$when the verdict is RECOVER (Part B) or TRIAGE / RED FLAGS (Part A)$n$),

-- 7. One GHL write per appointment (27 Oct duplicate)
(8, $o$New notes: POST /calendars/appointments/{appointmentId}/notes with {"body": "<html>", "userId": "<the appointment's assigned user id>"}. Immediately before the POST, read the notes once more; if a Note 1 appeared meanwhile, do not post.$o$,
$n$New notes: ONE POST per appointment per run, never two writes in flight for the same appointment (27 Oct: Vishnu Mate got two identical Note 1s 0.46 s apart). POST /calendars/appointments/{appointmentId}/notes with {"body": "<html>", "userId": "<the appointment's assigned user id>"}. Immediately before the POST, read the notes once more; if a Note 1 appeared meanwhile, do not post. After the POST, never retry on a slow or unclear response — read the notes and check instead.$n$),

-- 8. Verdict
(9, $o$2. VERDICT: TRIAGE if ANY red flag: "No - I can't invest" or a slow start, someone else decides, low urgency, answers flipped after an earlier disqualification, numbers that don't add up, no application on file, or a grade capped by the HARD CAPS. Otherwise CONFIRM. One gate + a single action.$o$,
$n$2. VERDICT = the closer's temperature read for the triage call (Closer Playbook → Sales Process; S.P.E.E.D. Step 4). One gate + one action, with the score, caps and signals in the VERDICT line (e.g. "score 2.8 → Good · invest: yes, start: this week, sole DM: yes, age 34, video: watched"):
   • HOT — investment strong (score 4), start ASAP/this week, sole decider, Instagram verified, Offer Breakdown video WATCHED (rule 7), no math gap, no cap. Action: "close on the triage call itself — summarise pain, ask which program, take the deposit/payment on this call; no separate strategy call needed".
   • CONFIRM — good fit, no weak signal, but the video is not confirmed watched. Action: "confirm the slot on the call (do not make it conditional), then send WhatsApp 1–3".
   • TRIAGE — any ONE weak signal: investment weak or vague, slow start, someone else decides or decider blank, low urgency, answers flipped after an earlier disqualification, numbers that don't add up, no application on file, or a grade capped by the HARD CAPS. Action: name the exact qualifier that settles it (money / authority / urgency / video) in one sentence.
   • RED FLAGS — two or more weak signals, or Junk / No IG. Action: "conditional confirm — send the two resources, reply WATCHED by <time> or the slot is cancelled; no reply → free community link, chapter closed". Junk leads are not dialed; say so.$n$),

-- 9. Content order
(10, $o$   VERDICT: TRIAGE/CONFIRM — score + gate + single action$o$,
$n$   VERDICT: HOT/CONFIRM/TRIAGE/RED FLAGS — score + gate + single action$n$),
(11, $o$   📅 Day DD Mon, H:MM AM/PM IST • closer • calendar (source) • booking/reschedule history and application count
   FORM (DD Mon) — Who / Numbers / Pain + money, newest submission only (opt-in only / no application variants as needed)
$o$,
$n$   📅 Day DD Mon, H:MM AM/PM IST • closer • calendar (source) • booking/reschedule history and application count • call status (new / confirmed / WATCHED / READY)
   FORM (DD Mon) — Who / Numbers / Pain + money, newest submission only (opt-in only / no application variants as needed). Quote the #1 struggle verbatim — it drives the script.
   BUCKET — one line: **B2C** (not online yet / no paying online clients) → the call is about why they want to go online • **B2B** (already selling online) → the call is about quality leads and charging high ticket. Name the bucket and the form answer that decides it.
$n$),
(12, $o$   ACTIVITY — per rule 8
   ASK THESE — 4–6 questions built on the prospect's OWN numbers, words, researched Instagram content or contradictions (first one = offer video; include "what changed?" when answers flipped)
   CALL IT — one line naming the offer to pitch (OFFER TO PITCH) and the stall fallback
$o$,
$n$   ACTIVITY — per rule 8, PLUS the pre-call status in one bullet: **Pre-call:** video watched? (tag / WATCHED / READY / unknown) • WhatsApp messages 1–5 already sent (from the conversation) • replied to us or not
   TRIAGE SCRIPT — replaces ASK THESE in Note 1. The Closer Playbook triage call, filled with the prospect's OWN words and numbers so the closer reads it off the note. One bullet per line, bold label, max 10:
     • **Opener:** "Hey <first name>, how's it going? I'm <closer first name>, Business Consultant at Independent Online Coach from Aakash's team. You booked a call for <Day> <time>, right?" — add "(switch to Hindi if they reply in Hindi)" when the form or Instagram is in Hindi.
     • **Pain:** "In the form you said your biggest challenge is '<#1 struggle verbatim>', correct?" then the TWO pain-sequence questions that fit their answer best (how long has this been going on • what's the worst part • what bothers you most • what after-effects in the business • how is it affecting you personally • what if this continues another 3–4 months).
     • **Urgency:** one consequence question built on their stated goal or deadline (e.g. "you want ₹3L/month by January — what happens if the leads stay junk till then?") then "So fixing this is a top priority right now, correct?"
     • **Why us:** "What made you decide to book a call with us?" — note the answer they should give (seen our client results; name the ad/case study they came from).
     • **Video:** if WATCHED: "Which program are you more inclined towards — any questions on the Offer Breakdown video?" • if not: "Have you gone through the videos on how we help coaches scale to 3–10L/month? Any reason? No worries — I'll share it on WhatsApp, watch it before our call so you come much more apprised."
     • **Money:** "For full transparency, the minimum investment to work with us is ₹1L. Are you comfortable investing that in your growth?" — then the branch for THEIR form answer: invest Yes → one line, move on • "manage the funds" / "maybe" / vague → "How much have you set aside to grow the business?" • "not in a position" → "Glad we figured out the fit now — I'll send a free resource that gives you a directional head start" (7 Secrets to 7 Figures) and end the call.
     • **Authority:** sole decision-maker Yes → confirm in one line • blank or No → "Who's involved in the decision — is it permission or respect? Make sure you get their buy-in before we connect, or bring them on the call."
     • **Contradiction (only if any):** one question on the biggest flip or math gap, in their numbers ("you wrote 50 clients at ₹30k per 3 months but ₹50k–1L a month — which is right?"); include "what changed?" when answers flipped.
     • **Close of triage:** HOT → "You're aligned with this — shall we get you onboarded right now? Do you have GPay open?" • otherwise → "You seem like a good fit — watch the resource by this evening and reply WATCHED on WhatsApp so I can confirm your <Day> <time> call."
   CALL IT — one line: the program by OFFER TO PITCH (Jumpstart ₹1.18L / Accelerator ₹3.54L / Multiplier ₹7.08L + founder on the call), the payment line (upfront, max two parts, no payment plans, ₹10k minimum deposit), and the stall fallback (free community). For HOT, start the line with "Close on this call:".
   WHATSAPP — one line: which Playbook messages to send and when — 1 (intro) + 2 (Power Funnel System + DFY Offer Stack, reply WATCHED) right after the triage call • 3 (meeting link + join rules; no-show = no reschedule) after WATCHED • 4 (Aakash 30L/M, Blue Pond ads, Premium Selling case studies) that night, only after WATCHED • 5 (good morning, reply READY) on call day. Mark any already sent ("1–2 sent 24 Oct").
$n$),

-- 10. Slack: generate once, copy; updates are one-liners (decision 3, 5 Nov)
(13, $o$then post the CURRENT Note 1 under that parent — cancelled titled "PRE-CALL NOTE 1 (UPDATED — CANCELLED)", no-show titled "PRE-CALL NOTE 1 (NO-SHOW DD Mon)". If the appointment has no Note 1 yet, write it first.$o$,
$n$then reply under that parent (Aakash, 5 Nov 2026 — the full note is generated ONCE and the same Slack text is copied; it is never re-posted for an update): Call Confirmed → post the current Note 1 Slack copy verbatim if that thread doesn't have it yet; Call Cancelled → ONE line "Note 1 updated — cancelled DD Mon, send the rebook WhatsApp today"; No-Show → ONE line "No-show DD Mon — Note 2 job takes it". If the appointment has no Note 1 yet, write it first.$n$),
(14, $o$If you edited it this run (reschedule / cancel) → post the new version titled "PRE-CALL NOTE 1 (UPDATED — RESCHEDULED to Day DD Mon H:MM)" or "(UPDATED — CANCELLED)". Otherwise post it$o$,
$n$If you edited it this run (reschedule / cancel) → do NOT re-post the full note: post ONE short line, "Note 1 updated — rescheduled to Day DD Mon H:MM (Nth time)" or "Note 1 updated — cancelled DD Mon, send the rebook WhatsApp today". Otherwise post it (the same Slack text in every thread — generate it once, never research or rewrite it for a second channel)$n$),

-- 11. Part B prices
(15, $o$Worth one manual call; pitch DIH ₹1.77L on a payment plan (or ₹3L DFY if real revenue ≥₹50k). Disqualified leads DO close (Dolly Singh was a disqualified app and paid ₹1.77L).$o$,
$n$Worth one manual call; pitch Sales Jumpstart ₹1.18L (or Sales Accelerator ₹3.54L if real revenue ≥₹50k), upfront or two parts, no payment plans. Disqualified leads DO close (Dolly Singh was a disqualified app and paid).$n$),
(16, $o$• NURTURE — other Average/Below Avg, real but not ready: DIH-focused WhatsApp/email nurture (case studies, payment plan), never Kickstarter.$o$,
$n$• NURTURE — other Average/Below Avg, real but not ready: Jumpstart-focused WhatsApp/email nurture (Offer Breakdown video first, case studies only after they watch it), then the free community (7 Secrets to 7 Figures); never Kickstarter, never a payment plan.$n$),
(17, $o$CALL IT — one line naming the offer (DIH on a payment plan, or DFY) and the stall fallback, or "Drop — no follow-up"$o$,
$n$CALL IT — one line naming the offer by OFFER TO PITCH (Jumpstart ₹1.18L or Accelerator ₹3.54L, upfront or two parts) and the stall fallback (free community), or "Drop — no follow-up"$n$),

-- 12. Part C prices
(18, $o$pitch the upgrade on this call — DIH ₹1.77L on a payment plan, or ₹3L DFY if real revenue ≥ ₹50k/month.$o$,
$n$pitch the upgrade on this call — Sales Jumpstart ₹1.18L (₹1L + GST), or Sales Accelerator ₹3.54L (₹3L + GST) if real revenue ≥ ₹50k/month; upfront or at most two parts, no payment plans, ₹10k minimum deposit.$n$)

  ) v(i, o, nw) order by i loop
    n := (length(t) - length(replace(t, r.o, ''))) / length(r.o);
    if n <> 1 then
      raise exception 'patch % : old text found % times', r.i, n;
    end if;
    t := replace(t, r.o, r.nw);
  end loop;
  update ai_jobs set instructions = t, updated_at = now() where slug = 'lead_notes';
end
$patch$;
