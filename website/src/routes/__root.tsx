import { HeadContent, Outlet, createRootRoute } from '@tanstack/react-router'

/** The root route: the head tags a page sets, then the page. */
export const Route = createRootRoute({
	component: () => (
		<>
			<HeadContent />
			<Outlet />
		</>
	),
})
