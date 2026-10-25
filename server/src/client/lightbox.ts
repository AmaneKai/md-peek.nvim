import { lightbox } from './dom.js'
import { store } from './store.js'

/** The click-to-zoom image dialog, driven by the store like the diagram viewer. */
export function initLightbox(): void {
  store.subscribe((state, previous) => {
    if (state.zoomedImage && state.zoomedImage !== previous.zoomedImage) {
      const preview = lightbox.querySelector('img')
      if (preview) {
        preview.src = state.zoomedImage
      }
      lightbox.showModal()
    }
  })

  lightbox.addEventListener('close', () => store.dispatch({ type: 'IMAGE_ZOOM_CLOSED' }))
  lightbox.addEventListener('click', (event) => {
    if (event.target === lightbox || (event.target as Element).closest('button')) {
      lightbox.close()
    }
  })
}
