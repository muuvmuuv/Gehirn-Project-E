import { useReducedMotion } from 'motion/react'
import type { MotionProps } from 'motion/react'

/** The strong ease-out every entrance on the site shares; --ease-out in src/styles/site.css is the same curve for CSS. */
export const EASE_OUT: [number, number, number, number] = [0.23, 1, 0.32, 1]

/** One step of a stagger, in seconds. */
export const STEP = 0.06

const VIEWPORT = { once: true, margin: '0px 0px -10% 0px', amount: 0.15 } as const

/**
 * Props that rise a motion element 18 px into place once it scrolls into view, the site's one
 * entrance. Pass `useReducedMotion()` as `reduce` inside loops; under reduced motion the element
 * renders in place.
 */
export function reveal(delay = 0, reduce: boolean | null = false): MotionProps {
	if (reduce) return {}
	return {
		initial: { opacity: 0, transform: 'translateY(18px)' },
		whileInView: { opacity: 1, transform: 'translateY(0px)' },
		viewport: VIEWPORT,
		transition: { duration: 0.7, ease: EASE_OUT, delay },
	}
}

/** `reveal` for call sites outside a loop. */
export function useReveal(delay = 0): MotionProps {
	return reveal(delay, useReducedMotion())
}
