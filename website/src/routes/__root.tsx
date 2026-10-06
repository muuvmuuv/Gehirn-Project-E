import { HeadContent, Link, Outlet, createRootRoute } from '@tanstack/react-router'
import { Footer } from '../components/Footer'
import { Nav } from '../components/Nav'

/** The root route: the head tags a page sets, and the shell every page shares around it. */
export const Route = createRootRoute({
	component: Shell,
	notFoundComponent: NotFound,
})

/** The shell of every page: the skip link, the hazard band, the nav, the page's main and the footer. */
function Shell() {
	return (
		<>
			<HeadContent />
			<div className="page">
				<a className="skip" href="#main">
					Skip to content
				</a>
				<div className="hazard" aria-hidden="true" />
				<div className="wrap">
					<Nav />
					<main id="main" tabIndex={-1}>
						<Outlet />
					</main>
					<Footer />
				</div>
			</div>
		</>
	)
}

/** The page for a path the site does not have, in the words of the bridge's verdict. */
function NotFound() {
	return (
		<div className="lost">
			<div className="eyebrow">
				<span className="jp">否決</span>
				<span>Not found</span>
			</div>
			<h1 className="h1">No such page</h1>
			<p className="lede">The site has a landing page and a guide to the bridge.</p>
			<p className="lost__links">
				<Link to="/">Home</Link>
				<Link to="/bridge">The bridge</Link>
			</p>
		</div>
	)
}
