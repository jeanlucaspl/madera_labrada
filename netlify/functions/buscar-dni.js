// Netlify Function: proxy para eldni.com
// Uso: /.netlify/functions/buscar-dni?dni=12345678

exports.handler = async function(event) {
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  }

  const dni = event.queryStringParameters?.dni
  if (!dni || !/^\d{8}$/.test(dni)) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'DNI inválido' }) }
  }

  try {
    const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

    // Step 1: obtener CSRF token y cookie de sesión
    const r1 = await fetch('https://eldni.com/pe/buscar-datos-por-dni', {
      headers: { 'User-Agent': UA }
    })
    const html1 = await r1.text()

    const tokenMatch = html1.match(/name="_token"\s+value="([^"]+)"/)
    if (!tokenMatch) return { statusCode: 502, headers, body: JSON.stringify({ error: 'Sin token CSRF', status: r1.status, html_preview: html1.slice(0, 300) }) }
    const token = tokenMatch[1]

    const rawCookies = r1.headers.getSetCookie ? r1.headers.getSetCookie() : []
    const cookieStr = rawCookies.map(c => c.split(';')[0]).join('; ')

    // Step 2: POST con el DNI
    const form = new FormData()
    form.append('_token', token)
    form.append('dni', dni)

    const r2 = await fetch('https://eldni.com/pe/buscar-datos-por-dni', {
      method: 'POST',
      headers: {
        'User-Agent': UA,
        'Cookie': cookieStr,
        'Referer': 'https://eldni.com/pe/buscar-datos-por-dni',
        'Origin': 'https://eldni.com',
      },
      body: form,
    })
    const html2 = await r2.text()

    // Parsear la tabla de resultados
    const tds = [...html2.matchAll(/<td[^>]*>\s*(.*?)\s*<\/td>/gis)]
    if (tds.length < 4) {
      return { statusCode: 404, headers, body: JSON.stringify({ error: 'DNI no encontrado' }) }
    }

    const strip = s => s.replace(/<[^>]+>/g, '').trim()

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        dni,
        nombres:          strip(tds[1][1]),
        apellido_paterno: strip(tds[2][1]),
        apellido_materno: strip(tds[3][1]),
      })
    }
  } catch(e) {
    return { statusCode: 500, headers, body: JSON.stringify({ error: e.message }) }
  }
}
