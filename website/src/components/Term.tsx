import { useEffect, useState } from 'react'

/** A shell command on a terminal line with a button that copies it, as `just demo` appears on every page. */
export function Term({ command, large = false }: { command: string; large?: boolean }) {
	const [state, setState] = useState<'idle' | 'copied' | 'failed'>('idle')

	useEffect(() => {
		if (state === 'idle') return
		const t = setTimeout(() => setState('idle'), 1600)
		return () => clearTimeout(t)
	}, [state])

	async function copy() {
		try {
			await navigator.clipboard.writeText(command)
			setState('copied')
		} catch {
			setState('failed')
		}
	}

	return (
		<div className={large ? 'term term--large' : 'term'}>
			<code>
				<span className="term__prompt" aria-hidden="true">
					${' '}
				</span>
				{command}
			</code>
			<button type="button" className="term__copy" onClick={copy}>
				<span aria-live="polite">
					{state === 'copied' ? 'Copied' : state === 'failed' ? 'Select it' : 'Copy'}
				</span>
			</button>
		</div>
	)
}
