import { REPO } from '../lib/site'
import { Term } from './Term'

/** The landing page's close: `just demo`, what it needs and where the docs go deeper. */
export function RunIt() {
	return (
		<section className="section" id="run" aria-labelledby="h-run">
			<div className="runit">
				<div>
					<h2 className="h2" id="h-run">
						Run it yourself
					</h2>
					<p>
						One command flies the whole story on scripted mock models, without keys. It needs V
						0.5.2, just, curl, unzip and Python 3.10 or newer, and is verified on Apple Silicon Macs
						and on Linux in containers.
					</p>
					<nav className="runit__links" aria-label="Docs">
						<a href={`${REPO}#try-it`}>Try it</a>
						<a href={`${REPO}/blob/main/docs/running.md`}>Running gehirn</a>
						<a href={`${REPO}/blob/main/docs/running.md#prebuilt-binaries`}>Prebuilt binaries</a>
					</nav>
				</div>
				<Term command="just demo" large />
			</div>
		</section>
	)
}
