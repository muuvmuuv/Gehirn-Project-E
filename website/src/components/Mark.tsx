/**
 * gehirn's mark, the entry plug's connector seen end on: a ring with one contact per MAGI unit, on
 * the 16 unit grid of docs/brand.md (assets/brand/mark.svg). Paper and orange, for the site's ink.
 */
export function Mark({ size = 32 }: { size?: number }) {
	return (
		<svg className="mark" viewBox="0 0 16 16" width={size} height={size} aria-hidden="true">
			<path
				fill="var(--paper)"
				fillRule="evenodd"
				d="M8 1a7 7 0 1 1 0 14A7 7 0 1 1 8 1m0 2a5 5 0 1 0 0 10A5 5 0 1 0 8 3"
			/>
			<path fill="var(--orange)" d="M7 4h2v2H7zM4 8h2v2H4zm6 0h2v2h-2z" />
		</svg>
	)
}
