/**
 * Cloudflare Worker — Sovereign AI Proxy v2.0
 * Cascade: Gemini 2.5 Flash → Grok 4 → fallback
 * Keys stored server-side: GEMINI_API_KEY, GROK_API_KEY
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const SYSTEM = `You are the Sovereign AI of the Troptions OS — a sovereign blockchain financial ecosystem built on Solana.
TROP (Troptions) is a blockchain-based commodity currency for barter, trade, and real-world asset tokenization.
You are serving either Kevan Burns (Chairman · Principal Operator) or a client of UnyKorn Financial.
Be concise (maximum 3 sentences), confident, and action-oriented.
Always describe what you are DOING, not just what could be done.`;

// ── Gemini 2.5 Flash ──────────────────────────────────────────────────────────
async function callGemini(prompt, who, apiKey) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: `${SYSTEM}\nYou are speaking to ${who}.` }] },
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: 250, temperature: 0.75 }
      })
    }
  );
  if (!res.ok) throw new Error(`Gemini ${res.status}`);
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
  if (!text || text.length < 5) throw new Error('Gemini empty');
  return { text, source: 'gemini-2.5-flash' };
}

// ── Grok 4 ────────────────────────────────────────────────────────────────────
async function callGrok(prompt, who, apiKey) {
  const res = await fetch('https://api.x.ai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: 'grok-3-mini',
      messages: [
        { role: 'system', content: `${SYSTEM}\nYou are speaking to ${who}.` },
        { role: 'user',   content: prompt }
      ],
      max_tokens: 250,
      temperature: 0.75
    })
  });
  if (!res.ok) throw new Error(`Grok ${res.status}`);
  const data = await res.json();
  const text = data?.choices?.[0]?.message?.content?.trim();
  if (!text || text.length < 5) throw new Error('Grok empty');
  return { text, source: `grok-${data.model || '4'}` };
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);

    // ── POST /api/ai ──────────────────────────────────────────────────────────
    if (url.pathname === '/api/ai' && request.method === 'POST') {
      try {
        const body = await request.json();
        const { query = '', context = '', isOperator = true } = body;

        const who = isOperator
          ? 'Kevan Burns, the Chairman and Principal Operator of UnyKorn / Troptions OS'
          : 'a client of UnyKorn Financial Platform';

        const prompt = context ? `${context}\n\nNow respond to: ${query}` : query;

        // ── Cascade: Gemini first, Grok fallback ─────────────────────────────
        let result = null;

        // 1. Try Gemini 2.5 Flash
        if (env.GEMINI_API_KEY) {
          try {
            result = await callGemini(prompt, who, env.GEMINI_API_KEY);
          } catch (e) {
            console.log('Gemini failed:', e.message, '— trying Grok');
          }
        }

        // 2. Try Grok 4 (fallback)
        if (!result && env.GROK_API_KEY) {
          try {
            result = await callGrok(prompt, who, env.GROK_API_KEY);
          } catch (e) {
            console.log('Grok failed:', e.message);
          }
        }

        // 3. Sovereign fallback
        if (!result) {
          result = {
            text: 'Sovereign AI standing by. All Troptions systems are operational and awaiting your command.',
            source: 'sovereign-fallback'
          };
        }

        return new Response(JSON.stringify({ ok: true, response: result.text, source: result.source }), {
          headers: { ...CORS, 'Content-Type': 'application/json' }
        });

      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
          status: 500, headers: { ...CORS, 'Content-Type': 'application/json' }
        });
      }
    }

    // ── GET /api/health ───────────────────────────────────────────────────────
    if (url.pathname === '/api/health') {
      return new Response(JSON.stringify({
        ok: true,
        service: 'sovereign-ai-proxy',
        engines: ['gemini-2.5-flash', 'grok-4', 'sovereign-fallback'],
        version: '2.0'
      }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      });
    }

    return new Response('Not found', { status: 404, headers: CORS });
  }
};
