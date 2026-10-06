import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'

import '@fontsource/barlow/400.css'
import '@fontsource/barlow/500.css'
import '@fontsource/barlow/600.css'
import '@fontsource/barlow-condensed/600.css'
import '@fontsource/barlow-condensed/700.css'
import '@fontsource/barlow-condensed/800.css'
import '@fontsource/barlow-condensed/900.css'
import '@fontsource/ibm-plex-mono/500.css'
import './styles/site.css'

import { routeTree } from './routeTree.gen'

// Zen Old Mincho's 120 subsets take about 100 KB of @font-face rules a weight, so they load after the
// first paint; the kanji show in the system's Mincho until then.
void import('@fontsource/zen-old-mincho/700.css')
void import('@fontsource/zen-old-mincho/900.css')

const router = createRouter({ routeTree, scrollRestoration: true })

declare module '@tanstack/react-router' {
	interface Register {
		router: typeof router
	}
}

createRoot(document.getElementById('root')!).render(
	<StrictMode>
		<RouterProvider router={router} />
	</StrictMode>,
)
