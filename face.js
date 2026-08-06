'use strict'
// ── Algoritmo de reconocimiento facial calibrado (Charly Táctico) ──────
// Parámetros idénticos al admin.html de la intranet: NO modificar sin recalibrar.
const FACIAL_UMBRAL         = 0.55   // distancia máxima para considerar match
const FACIAL_MATCH_NEEDED   = 3      // frames consecutivos para confirmar identidad
const FACIAL_DESCRIPTOR_DIM = 128
const FACE_MODEL_URL        = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1.7.12/model'

let _faceLoaded  = false
let _faceLoading = false

// Carga los 3 modelos de face-api una sola vez por sesión.
async function cargarModelosFace() {
  if (_faceLoaded) return
  if (_faceLoading) {
    return new Promise(r => {
      const iv = setInterval(() => { if (_faceLoaded) { clearInterval(iv); r() } }, 200)
    })
  }
  _faceLoading = true
  try {
    if (faceapi.tf) await faceapi.tf.ready()
    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromUri(FACE_MODEL_URL),
      faceapi.nets.faceLandmark68Net.loadFromUri(FACE_MODEL_URL),
      faceapi.nets.faceRecognitionNet.loadFromUri(FACE_MODEL_URL),
    ])
    // warm-up: evita lag en la primera detección real
    const wc = document.createElement('canvas'); wc.width = 416; wc.height = 416
    await faceapi.detectSingleFace(wc, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.2 }))
    _faceLoaded = true
  } catch (e) { console.warn('face-api: modelos no cargaron', e) }
}

// Calcula el descriptor facial de un Blob de imagen.
// Retorna Array[128] o null si no detecta rostro.
async function computarDescriptor(blob) {
  await cargarModelosFace()
  try {
    const img = await createImageBitmap(blob)
    const c = document.createElement('canvas')
    c.width = img.width; c.height = img.height
    c.getContext('2d').drawImage(img, 0, 0)
    const det = await faceapi
      .detectSingleFace(c, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.2 }))
      .withFaceLandmarks()
      .withFaceDescriptor()
    return det ? Array.from(det.descriptor) : null
  } catch { return null }
}

// Inicia el loop de verificación facial (200 ms/frame, 3 frames consecutivos para confirmar).
// descriptor: Array[128] del empleado logueado (guardado en perfiles.foto_descriptor)
// video: <video> con stream activo
// canvas: <canvas> superpuesto al video para el bounding box
// onStatus(msg): callback de estado (string)
// onMatch(pct): callback cuando se confirma la identidad (porcentaje de confianza)
// Retorna: función stop() para cancelar el loop
async function iniciarVerificacion({ video, canvas, descriptor, onStatus, onMatch }) {
  await cargarModelosFace()

  const stored  = new Float32Array(descriptor)
  const matcher = new faceapi.FaceMatcher(
    [new faceapi.LabeledFaceDescriptors('yo', [stored])],
    FACIAL_UMBRAL
  )
  let activo = true
  let streak = 0

  async function frame() {
    if (!activo) return
    if (!video.videoWidth) { setTimeout(frame, 200); return }

    canvas.width  = video.videoWidth
    canvas.height = video.videoHeight
    const ctx = canvas.getContext('2d')
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height)

    try {
      const det = await faceapi
        .detectSingleFace(canvas, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.2 }))
        .withFaceLandmarks()
        .withFaceDescriptor()

      ctx.clearRect(0, 0, canvas.width, canvas.height)

      if (!det) {
        streak = 0
        onStatus('Buscando rostro...')
        if (activo) setTimeout(frame, 200)
        return
      }

      const r   = faceapi.resizeResults(det, { width: video.videoWidth, height: video.videoHeight })
      const box = r.detection.box
      const mt  = matcher.findBestMatch(det.descriptor)
      const ok  = mt.label !== 'unknown'
      const pct = ok ? Math.round((1 - mt.distance) * 100) : null

      // Bounding box
      ctx.strokeStyle = ok ? '#5a9e6f' : '#c8a45a'
      ctx.lineWidth   = 3
      ctx.strokeRect(box.x, box.y, box.width, box.height)
      ctx.fillStyle   = ok ? 'rgba(90,158,111,0.15)' : 'rgba(200,164,90,0.1)'
      ctx.fillRect(box.x, box.y, box.width, box.height)
      ctx.fillStyle   = ok ? '#5a9e6f' : '#c8a45a'
      ctx.font        = 'bold 14px sans-serif'
      ctx.fillText(
        ok ? `${pct}% coincidencia` : 'Verificando...',
        box.x + 4,
        box.y > 20 ? box.y - 6 : box.y + box.height + 16
      )

      if (ok) {
        streak++
        onStatus(`Reconociendo... (${streak}/${FACIAL_MATCH_NEEDED})`)
        if (streak >= FACIAL_MATCH_NEEDED) {
          activo = false
          onMatch(pct)
          return
        }
      } else {
        streak = 0
        onStatus('Rostro detectado — verificando...')
      }
    } catch { /* frame skip sin romper el loop */ }

    if (activo) setTimeout(frame, 200)
  }

  frame()
  return () => { activo = false }
}
