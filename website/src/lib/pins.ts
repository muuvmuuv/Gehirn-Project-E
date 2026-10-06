/** A key on the bridge frame (public/bridge.png): where it sits, in percent of the frame, and the panel it names. */
export type Pin = { k: string; left: number; top: number; label: string }

/** The nine keys of the guide to the bridge, which the landing page's frame links into. */
export const PINS: Pin[] = [
	{ k: '1', left: 53.9, top: 3.2, label: 'header and status lights' },
	{ k: '2', left: 30, top: 42.6, label: 'the three MAGI judges' },
	{ k: '3', left: 16.2, top: 25.6, label: 'the proposal' },
	{ k: '4', left: 39.9, top: 21.9, label: 'the verdict' },
	{ k: '5', left: 96.9, top: 28.3, label: 'the umbilical clock' },
	{ k: '6', left: 95.3, top: 42.5, label: 'the scene radar' },
	{ k: '7', left: 13.3, top: 66.3, label: 'the sync ratio' },
	{ k: '8', left: 22.7, top: 87.5, label: 'the core' },
	{ k: '9', left: 79.4, top: 90, label: 'armor refusals and outcomes' },
]
