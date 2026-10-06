import type { ReactNode } from 'react'

/**
 * A panel in the bridge's frame: a hairline box with orange corner brackets and, when given a
 * label, a strip on top that names it in English and Japanese, the way the bridge heads its panels.
 */
export function Frame({
	label,
	jp,
	aside,
	className,
	children,
}: {
	label?: ReactNode
	jp?: string
	aside?: ReactNode
	className?: string
	children: ReactNode
}) {
	return (
		<div className={className ? `frame ${className}` : 'frame'}>
			{label !== undefined && (
				<div className="strip">
					<span>
						{label}
						{jp && <span className="strip__jp"> {jp}</span>}
					</span>
					{aside && <span className="strip__aside">{aside}</span>}
				</div>
			)}
			{children}
		</div>
	)
}
