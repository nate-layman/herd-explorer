// LLM bridge for the Ask page, adapted from Promptulus (github.com/AI4RA/promptulus, docs/js/api.js).
// One key box, four backends, chosen by the key's prefix:
//   - a University of Idaho MindRouter key ("mr2_") goes to MindRouter through the public
//     proxy on the lakehouse VM (MindRouter is campus-only; the proxy adds CORS headers);
//   - an Anthropic key ("sk-ant-") goes to Claude;
//   - any other "sk-" key goes to OpenAI's chat completions API;
//   - anything else is treated as a Google Gemini key.
// Routing by prefix avoids test calls that would send a key to a provider it does not belong to.
// The key lives in sessionStorage only (cleared when the tab closes); a ?key= link is read once
// and removed from the address bar.

export const MINDROUTER_BASE_URL = 'https://nlayman-external.insight.uidaho.edu/v1';
export const MINDROUTER_MODEL = 'qwen/qwen3.8-27b';
export const OPENAI_BASE_URL = 'https://api.openai.com/v1';
export const OPENAI_MODEL = 'gpt-6-astra';
export const ANTHROPIC_MODEL = 'claude-opus-5-5';
export const GEMINI_MODEL = 'gemini-3.8-flash';

const STORAGE_KEY = 'herd_explorer_llm_key';

export function getKey() {
  try { return sessionStorage.getItem(STORAGE_KEY) || ''; } catch { return ''; }
}

export function setKey(key) {
  try {
    if (key) sessionStorage.setItem(STORAGE_KEY, key.trim());
    else sessionStorage.removeItem(STORAGE_KEY);
  } catch { /* storage blocked: the key lasts only for this page view */ }
}

// Read ?key= once, keep it for this tab, and strip it so it does not linger in history or bookmarks
export function readKeyFromURL() {
  const url = new URL(location.href);
  const key = url.searchParams.get('key');
  if (key) {
    setKey(key);
    url.searchParams.delete('key');
    history.replaceState(null, '', url);
  }
  return getKey();
}

export const isMindRouterKey = k => typeof k === 'string' && k.trim().startsWith('mr2_');
// Checked before isOpenAIKey: Anthropic keys also start with "sk-"
export const isAnthropicKey = k => typeof k === 'string' && k.trim().startsWith('sk-ant-');
export const isOpenAIKey = k => typeof k === 'string' && k.trim().startsWith('sk-') && !isAnthropicKey(k);

export function backendName(key) {
  if (isMindRouterKey(key)) return 'MindRouter';
  if (isAnthropicKey(key)) return 'Anthropic Claude';
  if (isOpenAIKey(key)) return 'OpenAI';
  return 'Google Gemini';
}

/**
 * Send a conversation to whichever backend the key selects.
 * @param {string} systemPrompt
 * @param {Array<{role: 'user'|'model', text: string}>} history  earlier turns
 * @param {string} message  the new user turn
 * @returns {Promise<string>} the model's reply
 */
export async function callModel(systemPrompt, history, message) {
  const key = getKey();
  if (!key) throw new Error('Enter an API key first.');
  if (isMindRouterKey(key)) return chatCompletions(MINDROUTER_BASE_URL, MINDROUTER_MODEL, 'MindRouter', key, systemPrompt, history, message);
  if (isAnthropicKey(key)) return anthropic(key, systemPrompt, history, message);
  if (isOpenAIKey(key)) return chatCompletions(OPENAI_BASE_URL, OPENAI_MODEL, 'OpenAI', key, systemPrompt, history, message);
  return gemini(key, systemPrompt, history, message);
}

async function gemini(key, systemPrompt, history, message) {
  const { GoogleGenAI } = await import('https://esm.run/@google/genai@2.28.0');
  const ai = new GoogleGenAI({ apiKey: key });
  const contents = history.map(t => ({ role: t.role, parts: [{ text: t.text }] }));
  contents.push({ role: 'user', parts: [{ text: message }] });
  const response = await ai.models.generateContent({ model: GEMINI_MODEL, contents, config: { systemInstruction: systemPrompt } });
  return response.text;
}

async function anthropic(key, systemPrompt, history, message) {
  const { default: Anthropic } = await import('https://esm.run/@anthropic-ai/sdk@0.133.0');
  // The visitor's own key lives only in this page, so a browser call is the intended use
  const client = new Anthropic({ apiKey: key, dangerouslyAllowBrowser: true });
  const messages = history.map(t => ({ role: t.role === 'model' ? 'assistant' : t.role, content: t.text }));
  messages.push({ role: 'user', content: message });
  let response;
  try {
    response = await client.beta.messages.create({
      model: ANTHROPIC_MODEL,
      max_tokens: 8000,
      system: systemPrompt,
      messages,
      // Writing SQL over a documented schema needs little deliberation; low effort keeps replies quick and cheap
      output_config: { effort: 'low' },
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
    });
  } catch (e) {
    if (e instanceof Anthropic.AuthenticationError) throw new Error('Anthropic rejected the API key. Check it and try again.');
    if (e instanceof Anthropic.RateLimitError) throw new Error('Anthropic rate limit reached. Wait a minute and try again.');
    if (e instanceof Anthropic.APIConnectionError) throw new Error(`Could not reach Anthropic (${e.message}).`);
    throw new Error(`Anthropic error${e.status ? ' ' + e.status : ''}: ${e.message}`);
  }
  if (response.stop_reason === 'refusal') throw new Error('Claude declined to answer this request. Try rephrasing it.');
  const text = response.content.filter(b => b.type === 'text').map(b => b.text).join('');
  if (!text) throw new Error('Anthropic returned no text.');
  return text.trim();
}

// OpenAI chat completions format, shared by OpenAI and MindRouter
async function chatCompletions(baseUrl, model, name, key, systemPrompt, history, message) {
  const messages = [{ role: 'system', content: systemPrompt }];
  for (const t of history) messages.push({ role: t.role === 'model' ? 'assistant' : t.role, content: t.text });
  messages.push({ role: 'user', content: message });
  let response;
  try {
    response = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ model, messages }),
    });
  } catch (e) {
    throw new Error(`Could not reach ${name} (${e.message}).`);
  }
  if (!response.ok) {
    let detail = '';
    try { const err = await response.json(); detail = err.detail || err.error?.message || err.error || ''; } catch { /* not JSON */ }
    if (response.status === 401) throw new Error(`${name} rejected the API key. Check it and try again.`);
    if (response.status === 429) throw new Error(`${name} rate limit or quota reached${detail ? ': ' + detail : ''}`);
    throw new Error(`${name} error ${response.status}${detail ? ': ' + detail : ''}`);
  }
  const data = await response.json();
  let text = data.choices?.[0]?.message?.content;
  if (typeof text !== 'string') throw new Error(`${name} returned no text.`);
  // Thinking models sometimes leave their reasoning inline; never show it
  return text.replace(/<think>[\s\S]*?<\/think>\s*/g, '').trim();
}
