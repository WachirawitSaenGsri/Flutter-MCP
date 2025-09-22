import 'dotenv/config';
import { WebSocketServer, WebSocket } from 'ws';
import { GoogleGenerativeAI } from '@google/generative-ai';

// ====== Config ======
const PORT = process.env.PORT ? Number(process.env.PORT) : 8787;
const MODEL = process.env.MODEL || 'gemini-1.5-flash';
const SYSTEM_PROMPT = (
  process.env.SYSTEM_PROMPT ||
  'You are a helpful AI assistant inside a Flutter app. Answer clearly, use markdown for code, and be concise.'
);
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
if (!GEMINI_API_KEY) {
  console.warn('[gateway] Missing GEMINI_API_KEY');
}

// ====== Gemini init ======
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const baseModel = genAI.getGenerativeModel({
  model: MODEL,
  systemInstruction: SYSTEM_PROMPT,
});

// ====== WebSocket server ======
const wss = new WebSocketServer({ port: PORT, path: '/stream' });
console.log(`[gateway] ws listening on ws://localhost:${PORT}/stream`);

wss.on('connection', (socket: WebSocket) => {
  console.log('[gateway] client connected');

  // เก็บข้อความแบบง่าย ๆ ต่อเซสชัน (หน่วยความจำชั่วคราว)
  const history: Array<{ role: 'user' | 'model'; text: string }> = [];

  socket.on('message', async (raw) => {
    let msg: any;
    try { msg = JSON.parse(String(raw)); } catch { return; }

    if (msg.type === 'hello') {
      // TODO: ตรวจสอบ token/auth ที่นี่ถ้าต้องการ
      return;
    }

    if (msg.type === 'user_message') {
      const userText: string = (msg.text ?? '').toString();
      const conversationId: string | undefined = msg.conversationId;

      history.push({ role: 'user', text: userText });

      try {
        // เตรียมข้อความให้ Gemini (สไตล์ content parts)
        const contents = [
          ...history.map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.text }] })),
        ];

        const streamingResp = await baseModel.generateContentStream({ contents });

        let assistantText = '';
        for await (const chunk of streamingResp.stream) {
          const delta = chunk.text();
          if (delta) {
            assistantText += delta;
            socket.send(JSON.stringify({ type: 'assistant_delta', delta }));
          }
        }

        socket.send(JSON.stringify({
          type: 'assistant_done',
          messageId: Date.now().toString(),
          conversationId,
        }));

        history.push({ role: 'model', text: assistantText });

        // ตัวอย่าง tool message เมื่อผู้ใช้ถามเวลา/วันที่
        if (/(?:time|date|เวลา|วันที่)/i.test(userText)) {
          socket.send(JSON.stringify({
            type: 'tool_message',
            name: 'clock.now',
            content: new Date().toISOString(),
          }));
        }
      } catch (err: any) {
        console.error('[gateway] gemini error:', err?.message || err);
        socket.send(JSON.stringify({ type: 'error', message: 'Model error: ' + (err?.message || 'unknown') }));
      }
    }

    // Optional: รองรับ direct tool calls แล้ว route ไป MCP
    // if (msg.type === 'tool_invoke') { /* เรียก MCP แล้วส่งคืน tool_message */ }
  });

  socket.on('close', () => console.log('[gateway] client disconnected'));
});