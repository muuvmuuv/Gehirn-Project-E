import { createFileRoute, redirect } from '@tanstack/react-router'

/** The landing page; until it lands, the guide to the bridge stands in for it. */
export const Route = createFileRoute('/')({
	beforeLoad: () => {
		throw redirect({ to: '/bridge', replace: true })
	},
})
