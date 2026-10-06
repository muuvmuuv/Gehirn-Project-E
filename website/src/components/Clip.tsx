import { useInView, useReducedMotion } from 'motion/react'
import { useEffect, useRef } from 'react'

/**
 * A recording of the bridge: muted and looping, it plays only while it is on screen, so a page
 * with several clips downloads the one in view. Under reduced motion it stays on its poster. Its
 * controls let a viewer stop it, which WCAG asks of motion that plays longer than 5 s. Every clip
 * on the site is 1280 by 800 or, for the MAGI block, 800 by 448.
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

	useEffect(() => {
		const v = ref.current
		if (!v || reduce) return

		// play() rejects when the browser blocks it or a newer pause() wins; the poster stays, which is fine.
		if (inView) v.play().catch(() => {})
		else v.pause()
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
			preload={eager ? 'auto' : 'none'}
		/>
	)
}
