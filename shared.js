'use strict'
const SUPABASE_URL      = 'https://pfwtrdfikkmknhrueeuj.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmd3RyZGZpa21ra25ocnVlZXVqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4MDU3NzksImV4cCI6MjA5NjM4MTc3OX0.jo00QI8lTGqamb2kelS4Kf5ts9sLI6eMAC8I6mRNrfg'

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// Verifica sesión. Redirige a login si no hay sesión o perfil inactivo.
// Si rolEsperado es 'admin' y el usuario es 'empleado', redirige a empleado.html y viceversa.
async function requireAuth(rolEsperado = null) {
  const { data: { session } } = await sb.auth.getSession()
  if (!session) { location.href = 'login.html'; return null }

  const { data: perfil } = await sb.from('perfiles').select('*').eq('id', session.user.id).single()
  if (!perfil || !perfil.activo) { await sb.auth.signOut(); location.href = 'login.html'; return null }

  if (rolEsperado && perfil.rol !== rolEsperado) {
    location.href = perfil.rol === 'admin' ? 'admin.html' : 'empleado.html'
    return null
  }
  return perfil
}

function hoy() { return new Date().toISOString().slice(0, 10) }

function fmtFecha(str) {
  if (!str) return '—'
  const [y, m, d] = str.split('-')
  const M = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic']
  return `${d} ${M[+m - 1]} ${y}`
}

function fmtHora(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })
}

// Retorna diferencia en horas (decimal) entre dos ISO strings. null si alguno falta.
function diffHoras(iso1, iso2) {
  if (!iso1 || !iso2) return null
  const h = (new Date(iso2) - new Date(iso1)) / 3600000
  return Math.round(h * 100) / 100
}

let _alertTimer = null
function showAlert(msg, tipo = 'ok') {
  const el = document.getElementById('global-alert')
  if (!el) return
  el.textContent = msg
  el.className = `global-alert alert-${tipo}`
  el.style.display = 'block'
  clearTimeout(_alertTimer)
  _alertTimer = setTimeout(() => { el.style.display = 'none' }, 4500)
}
