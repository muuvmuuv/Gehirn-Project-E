import { Link } from '@tanstack/react-router'
import { REPO } from '../lib/site'

/**
 * The header of every page: the lockup the README shows, linking home, the bridge's three status
 * lights as ornament, and the sections. The lights show no state; the bridge's own show the
 * running stack's.
 */
export function Nav() {
	return (
		<header className="nav">
			<Link to="/" className="brand" aria-label="gehirn, home">
				{/* docs/brand.md sets the lockup's smallest width at 200 px, where ゲヒルン E計画 stays legible. */}
				<img src="/lockup-dark.svg" alt="" width={200} height={64} />
			</Link>
			<div className="lights" aria-hidden="true">
				<span>
					<i /> FIELD <em>LIVE</em>
				</span>
				<span>
					<i /> HQ <em>LINK</em>
				</span>
				<span>
					<i /> MAGI <em>STANDBY</em>
				</span>
			</div>
			<nav className="links" aria-label="Sections">
				<Link to="/" hash="how">
					How it works
				</Link>
				<Link to="/" hash="scenes">
					Scenes
				</Link>
				<Link to="/bridge" className="links__page">
					The bridge
				</Link>
				<a className="links__gh" href={REPO}>
					GitHub ↗
				</a>
			</nav>
		</header>
	)
}
