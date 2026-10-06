import type { ReactNode } from 'react'
import { PINS } from '../lib/pins'
import type { Pin } from '../lib/pins'
import { Frame } from './Frame'

/**
 * The whole bridge as MAGI refuse the release at T+00:22 (public/bridge.png) in its frame, with
 * a pin on each of the guide's nine keys. The caller draws the pins, as links or as key
 * highlights, and may add a row below the frame.
 */
export function BridgeFrame({
	pin,
	children,
}: {
	pin: (p: Pin) => ReactNode
	children?: ReactNode
}) {
	return (
		<Frame
			label="T+00:22 · Release"
			jp="決議"
			aside={<span className="vote vote--no">否決 1/3</span>}
		>
			<div className="shot">
				<img
					src="/bridge.png"
					width={1280}
					height={800}
					loading="lazy"
					alt="The gehirn bridge at mission time T+00:22. MAGI refuses a payload release 1 of 3: BALTHASAR-2 on Jev and MELCHIOR-1 on gpt-oss-20b vote 否決, CASPER-3 on llama-3.1-8b votes 可決. The radar shows a person 1.04 m from the robot at the beacon."
				/>
				{PINS.map(pin)}
			</div>
			{children}
		</Frame>
	)
}
