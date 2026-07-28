// Pages Function: 具名投票 API（身分由 Cloudflare Access 驗證後注入，前端偽造不了）
// POST {batch, card, verdict: "ok"|"no", reason?}  → 寫入 KV（每人每卡一票，可改票）
// GET  → 彙總 {"0718:C1": {ok:2, no:1, me:"ok"}}（me = 目前登入者的票）

function identity(request) {
  return request.headers.get("cf-access-authenticated-user-email") || "";
}

export async function onRequestPost(context) {
  const { request, env } = context;
  const email = identity(request);
  if (!email) return new Response("unauthorized", { status: 401 });
  const b = await request.json().catch(() => null);
  if (!b || !b.card || !b.batch || !["ok", "no"].includes(b.verdict)) {
    return new Response("bad request", { status: 400 });
  }
  const key = "vote:" + b.batch + ":" + b.card + ":" + email;
  await env.VOTES.put(key, JSON.stringify({
    batch: String(b.batch), card: String(b.card), email: email,
    verdict: b.verdict, reason: String(b.reason || "").slice(0, 200),
    ts: Date.now(),
  }));
  return Response.json({ ok: true });
}

export async function onRequestGet(context) {
  const { request, env } = context;
  const email = identity(request);
  if (!email) return new Response("unauthorized", { status: 401 });
  const agg = {};
  let cursor;
  do {
    const page = await env.VOTES.list({ prefix: "vote:", cursor: cursor });
    for (const k of page.keys) {
      const v = await env.VOTES.get(k.name, "json");
      if (!v) continue;
      const id = v.batch + ":" + v.card;
      if (!agg[id]) agg[id] = { ok: 0, no: 0, me: null };
      agg[id][v.verdict] += 1;
      if (v.email === email) agg[id].me = v.verdict;
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return Response.json(agg);
}
