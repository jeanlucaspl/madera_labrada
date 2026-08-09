// Netlify Function: proxy para eldni.com
exports.handler = async function(event) {
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  }

  const dni = event.queryStringParameters?.dni
  if (!dni || !/^\d{8}$/.test(dni)) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'DNI inválido' }) }
  }

  const browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'es-PE,es;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Cache-Control': 'max-age=0',
  }

  try {
    // Step 1: GET para obtener CSRF token y cookies
    const r1 = await fetch('https://eldni.com/pe/buscar-datos-por-dni', {
      headers: browserHeaders,
      redirect: 'follow',
    })

    if (!r1.ok) {
      return { statusCode: 502, headers, body: JSON.stringify({ error: `eldni.com GET ${r1.status}` }) }
    }

    const html1 = await r1.text()
    const tokenMatch = html1.match(/name="_token"\s+value="([^"]+)"/)
    if (!tokenMatch) {
      return { statusCode: 502, headers, body: JSON.stringify({ error: 'Sin token CSRF', preview: html1.slice(0, 200) }) }
    }
    const token = tokenMatch[1]

    // Extraer cookies
    const rawCookies = r1.headers.getSetCookie ? r1.headers.getSetCookie() : []
    const cookieStr = rawCookies.map(c => c.split(';')[0]).join('; ')

    // Step 2: POST con el DNI
    const form = new FormData()
    form.append('_token', token)
    form.append('dni', dni)

    const r2 = await fetch('https://eldni.com/pe/buscar-datos-por-dni', {
      method: 'POST',
      headers: {
        ...browserHeaders,
        'Cookie': cookieStr,
        'Referer': 'https://eldni.com/pe/buscar-datos-por-dni',
        'Origin': 'https://eldni.com',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-User': '?1',
      },
      body: form,
      redirect: 'follow',
    })

    const html2 = await r2.text()
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
