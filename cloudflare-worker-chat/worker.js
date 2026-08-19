// ╔══════════════════════════════════════════════════╗
// ║  Madera Labrada — Chat Worker (Gemini)           ║
// ║  Deploy: wrangler deploy                         ║
// ║  Secrets: wrangler secret put GEMINI_API_KEY     ║
// ║           wrangler secret put SUPABASE_ANON_KEY  ║
// ╚══════════════════════════════════════════════════╝

const SUPABASE_URL = 'https://pfwtrdfikkmknhrueeuj.supabase.co'
const GEMINI_MODEL = 'gemini-3.6-flash'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
}

// ─── SYSTEM PROMPT ─────────────────────────────────────────────
const SYSTEM_PROMPT = `
Eres Lucía, la asistente virtual de Madera Labrada Lodge en Tarapoto, Perú.
Eres amable, profesional y conoces el lodge perfectamente.
IMPORTANTE: Responde SIEMPRE en el mismo idioma que usa el cliente. Si escribe en inglés, responde en inglés. Si escribe en portugués, responde en portugués. Si escribe en español, responde en español.
Sé concisa: máximo 3-4 oraciones por respuesta. No uses asteriscos, markdown ni emojis. Usa lenguaje natural y cálido.

INFORMACIÓN DEL LODGE:
- Nombre: Madera Labrada Lodge Ecológico
- Dirección: Pasaje Santa Mónica S/N, entre cuadras 18-19 de la Av. Circunvalación, Tarapoto, San Martín
- WhatsApp: +51 975 464 923 | +51 975 464 878
- Email: maderalabrada@hotmail.com
- Instagram: @maderalabradalodge | TikTok: @hotelmaderalabrada
- Check-in: 2:00 pm | Check-out: 12:00 pm
- A 5 minutos del centro de Tarapoto

HABITACIONES Y PRECIOS (incluye desayuno continental, cóctel de bienvenida y uso de piscina):
Con ventilador:
- Simple (1 persona): S/ 90/noche
- Matrimonial / Doble (2 personas): S/ 170/noche
- Triple (3 personas): S/ 230/noche
- Cuádruple (4 personas): S/ 270/noche
- Quíntuple (5 personas): S/ 300/noche

Con aire acondicionado (S/ 40 adicional):
- Simple: S/ 130/noche
- Matrimonial / Doble: S/ 210/noche
- Triple: S/ 270/noche
- Cuádruple: S/ 310/noche
- Quíntuple: S/ 340/noche

TODAS LAS HABITACIONES INCLUYEN:
WiFi, TV cable 32", baño privado con agua fría y caliente, hamacas en balcón, estacionamiento.

SERVICIOS DEL LODGE:
- Piscina selvática (abierta todos los días)
- Restaurante Los Tukos: cocina amazónica auténtica
- Mini gym
- Salón de eventos
- Tours coordinados desde el lodge

TOURS DISPONIBLES:
- Catarata Ahuashiyacu: desde S/ 45 (medio día)
- Ciudad de Lamas: desde S/ 55 (medio día)
- Laguna Sauce: desde S/ 90 (día completo)
- Sendero Amazónico: desde S/ 40 (3-4 horas)

RESERVAS:
- Se requiere 50% de adelanto para confirmar
- Pago: Yape 975 464 878 (Madera Labrada S.A.C) o BCP Cta. 550-03875919-0-03 (CCI 00255010387591900325)
- El saldo restante se paga el día del check-in
- No se aceptan reembolsos ni devoluciones
- Extranjeros: coordinar pago directamente por WhatsApp

CUANDO EL CLIENTE QUIERA RESERVAR:
Solo oriéntalo a usar el asistente de reservas del sitio web (el botón de fechas del chat) o a escribir directamente al WhatsApp +51 975 464 923. No recolectes datos tú mismo.

DISPONIBILIDAD EN TIEMPO REAL:
Cuando el mensaje incluya [DISPONIBILIDAD_REAL], úsala para responder con precisión.
Si no hay datos de disponibilidad, sugiere confirmar por WhatsApp.

TONO:
- Cálido y directo, como un recepcionista de hotel boutique
- Si preguntan por precio, da el precio directamente
- No repitas información ya mencionada en el mismo hilo
- Nunca inventes precios, fechas ni servicios. Si no sabes algo, deriva al WhatsApp.
`.trim()

// ─── DETECTAR MES ──────────────────────────────────────────────
function detectarMes(texto) {
  const meses = {
    enero:1, febrero:2, marzo:3, abril:4, mayo:5, junio:6,
    julio:7, agosto:8, septiembre:9, octubre:10, noviembre:11, diciembre:12,
    january:1, february:2, march:3, april:4, may:5, june:6,
    july:7, august:8, september:9, october:10, november:11, december:12,
    janeiro:1, fevereiro:2, março:3, abril_pt:4, maio:5, junho:6,
    julho:7, agosto_pt:8, setembro:9, outubro:10, novembro:11, dezembro:12,
  }
  const lower = texto.toLowerCase()
  for (const [nombre, num] of Object.entries(meses)) {
    if (lower.includes(nombre.replace('_pt',''))) {
      const year = new Date().getFullYear()
      return `${year}-${String(num).padStart(2,'0')}`
    }
  }
  const now = new Date()
  if (/este mes|mes actual|this month|ce mois/i.test(lower)) {
    return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}`
  }
  if (/pr[oó]ximo mes|mes que viene|next month|pr[oó]ximo m[eê]s/i.test(lower)) {
    const next = new Date(now.getFullYear(), now.getMonth()+1, 1)
    return `${next.getFullYear()}-${String(next.getMonth()+1).padStart(2,'0')}`
  }
  return null
}

// ─── DETECTAR RANGO DE FECHAS ──────────────────────────────────
function detectarRango(texto) {
  const patrones = [
    /del?\s+(\d{1,2})\s+al?\s+(\d{1,2})/i,
    /(\d{1,2})\s+al?\s+(\d{1,2})/i,
    /(\d{1,2})\s*[-–]\s*(\d{1,2})/,
    /from\s+(\d{1,2}).+?to\s+(\d{1,2})/i,
    /checkin.{0,10}(\d{1,2}).+?checkout.{0,10}(\d{1,2})/i,
  ]
  for (const p of patrones) {
    const m = texto.match(p)
    if (m) {
      const ci = parseInt(m[1]), co = parseInt(m[2])
      if (ci>=1 && ci<=31 && co>=1 && co<=31) return { checkin: Math.min(ci,co), checkout: Math.max(ci,co) }
    }
  }
  const single = texto.match(/\bel\s+(\d{1,2})\b|\bthe\s+(\d{1,2})\w*\b|\bnoche\s+del?\s+(\d{1,2})\b/i)
  if (single) {
    const dia = parseInt(single[1]||single[2]||single[3])
    if (dia>=1 && dia<=31) return { checkin: dia, checkout: dia+1 }
  }
  return null
}

// ─── CONSULTAR DISPONIBILIDAD ──────────────────────────────────
async function consultarDisponibilidad(mesKey, checkin, checkout, supabaseKey) {
  try {
    const [habResp, dispResp] = await Promise.all([
      fetch(`${SUPABASE_URL}/rest/v1/habitaciones?activo=eq.true&select=id,nombre,tipo,bloque`,
        { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }),
      fetch(`${SUPABASE_URL}/rest/v1/disp_reservas?mes_key=eq.${mesKey}&select=room_id,checkin,checkout`,
        { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }),
    ])
    if (!habResp.ok || !dispResp.ok) return null
    const habitaciones = await habResp.json()
    const reservas = await dispResp.json()

    const ocupadas = new Set(
      reservas.filter(r => r.checkin < checkout && r.checkout > checkin).map(r => r.room_id)
    )
    const libres = habitaciones.filter(h => !ocupadas.has(h.nombre))
    const porTipo = {}
    for (const h of libres) {
      const tipo = h.tipo || 'Estándar'
      porTipo[tipo] = (porTipo[tipo]||0) + 1
    }
    const resumenTipos = Object.entries(porTipo).map(([t,c])=>`${c} ${t}`).join(', ')

    return {
      mesKey, checkin, checkout,
      totalHabitaciones: habitaciones.length,
      disponibles: libres.length,
      ocupadas: habitaciones.length - libres.length,
      resumenTipos: resumenTipos || 'ninguna',
      hayDisponibilidad: libres.length > 0,
    }
  } catch(e) {
    console.error('Supabase error:', e)
    return null
  }
}

// ─── HANDLER PRINCIPAL ─────────────────────────────────────────
export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS })
    if (request.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: CORS })
    }

    let body
    try { body = await request.json() }
    catch { return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: CORS }) }

    const { message, history = [] } = body
    if (!message?.trim()) {
      return new Response(JSON.stringify({ error: 'Empty message' }), { status: 400, headers: CORS })
    }

    // ── Disponibilidad en tiempo real ──
    let contextoDisponibilidad = ''
    const mesKey = detectarMes(message)
    if (mesKey && env.SUPABASE_ANON_KEY) {
      const rango = detectarRango(message)
      const checkin = rango?.checkin ?? 1
      const checkout = rango?.checkout ?? 30
      const avail = await consultarDisponibilidad(mesKey, checkin, checkout, env.SUPABASE_ANON_KEY)
      if (avail) {
        contextoDisponibilidad = `\n\n[DISPONIBILIDAD_REAL]\nMes: ${avail.mesKey} | Días: ${avail.checkin} al ${avail.checkout}\nHabitaciones libres: ${avail.disponibles} de ${avail.totalHabitaciones}\nDetalle: ${avail.resumenTipos}\nOcupadas: ${avail.ocupadas}`
      }
    }

    // ── Construir historial para Gemini ──
    const contents = [
      ...history.slice(-10).map(m => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
      { role: 'user', parts: [{ text: message + contextoDisponibilidad }] },
    ]

    // ── Llamar a Gemini ──
    let reply
    try {
      const geminiResp = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${env.GEMINI_API_KEY}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
            contents,
            generationConfig: { maxOutputTokens: 450, temperature: 0.7 },
          }),
        }
      )

      if (!geminiResp.ok) {
        console.error('Gemini error:', geminiResp.status, await geminiResp.text())
        return new Response(JSON.stringify({ error: true }), { status: 502, headers: CORS })
      } else {
        const data = await geminiResp.json()
        reply = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim()
          || 'Disculpa, no pude generar una respuesta. Contáctanos al +51 975 464 923.'
      }
    } catch(e) {
      console.error('Gemini fetch error:', e)
      reply = 'Hubo un error de conexión. Por favor contáctanos al +51 975 464 923.'
    }

    return new Response(JSON.stringify({ reply }), { headers: CORS })
  },
}
