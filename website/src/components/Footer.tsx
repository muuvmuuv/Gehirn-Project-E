import { Link } from '@tanstack/react-router'
import { FAN_LINE, REPO } from '../lib/site'
import { Mark } from './Mark'

/** The footer of every page: the fan project line, the license and the links. */
export function Footer() {
	return (
		<footer className="footer">
			<div className="footer__fan">
				<Mark size={22} />
				<span>{FAN_LINE}</span>
			</div>
			<nav className="footer__links" aria-label="More">
				<Link to="/bridge">The bridge</Link>
				<a href={REPO}>Code on GitHub</a>
				<a href={`${REPO}/blob/main/LICENSE`}>EUPL 1.2</a>
			</nav>
		</footer>
	)
}
