import { Link } from '@tanstack/react-router'
import { BridgeFrame } from './BridgeFrame'

/** The landing page's look at the whole bridge, each pin a link into the guide's key. */
export function BridgeTeaser() {
	return (
		<section className="section" id="bridge" aria-labelledby="h-bridge">
			<div className="head">
				<h2 className="h2" id="h-bridge">
					Reading the bridge <span className="jp">発令所</span>
				</h2>
				<p>
					The operator's view of one robot. It only watches: nothing on it can steer, approve or
					eject.
				</p>
			</div>
			<BridgeFrame
				pin={(p) => (
					<Link
						key={p.k}
						className="pin"
						to="/bridge"
						hash={`k${p.k}`}
						style={{ left: `${p.left}%`, top: `${p.top}%` }}
						aria-label={`${p.k}: ${p.label}, in the guide`}
					>
						{p.k}
					</Link>
				)}
			>
				<div className="teaser__more">
					<p>
						Nine panels, the four vote states, the Japanese on screen and the demo beat by beat.
					</p>
					<Link to="/bridge">Read every panel →</Link>
				</div>
			</BridgeFrame>
		</section>
	)
}
