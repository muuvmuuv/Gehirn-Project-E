import { useInView, useReducedMotion } from 'motion/react'
import { useEffect, useRef } from 'react'

/**
 * A recording of the bridge: muted and looping, it plays only while it is on screen, so a page
 * with several clips downloads the one in view. Under reduced motion it stays on its poster. Its
 * controls let a viewer stop it, which WCAG asks of motion that plays longer than 5 s, and a clip
 * the viewer paused stays paused when it scrolls back into view. Every clip on the site is 1280
 * by 800, or 800 by 448 for the MAGI block and 1016 by 704 for the radar.
 */
export function Clip({
	src,
	poster,
	label,
	width = 1280,
	height = 800,
	eager = false,
}: {
	src: string
	poster: string
	label: string
	width?: number
	height?: number
	eager?: boolean
}) {
	const ref = useRef<HTMLVideoElement>(null)
	const reduce = useReducedMotion()
	const inView = useInView(ref, { amount: 0.35 })

	/** Whether the viewer paused the clip with its controls. */
	const held = useRef(false)

	/** Whether the next pause event is the clip's own, for leaving the screen or for reduced motion. */
	const ours = useRef(false)

	useEffect(() => {
		const v = ref.current
		if (!v) return

		if (reduce || !inView) {
			if (!v.paused) {
				ours.current = true
				v.pause()
			}
			return
		}

		// play() rejects when the browser blocks it or a newer pause() wins; the poster stays, which is fine.
		if (!held.current) v.play().catch(() => {})
	}, [inView, reduce])

	return (
		<video
			ref={ref}
			className="clip"
			src={src}
			poster={poster}
			width={width}
			height={height}
			aria-label={label}
			muted
			loop
			playsInline
			controls
			preload={eager && !reduce ? 'auto' : 'none'}
			onPlay={() => {
				held.current = false
			}}
			onPause={() => {
				if (ours.current) ours.current = false
				else held.current = true
			}}
		/>
	)
}
