# Launch

This page is for the owner, taking gehirn public: the steps in order, what the scan before it found, the thread for X with its media, the replies to expect and what to watch afterwards. Every number in the posts comes from PLAN's State or an ADR, with the day it was measured, so a reply that questions one can be answered from the repository.

## Steps

1. Read [Scan results](#scan-results), and run the scan again on the commit you make public, since commits land after it: `gitleaks git --redact --verbose` in the main checkout.
2. Push main, the commit you scanned, to GitHub. Vercel deploys what GitHub holds, and the public repository shows it.
3. Deploy the website on Vercel: Add New, Project, import `muuvmuuv/Gehirn-Project-E`, set the root directory to `website`, the framework preset to Other, and leave the build command empty, since the folder is the site. Vercel serves only that folder ([decisions](decisions.md#tooling)).
4. Set the domain. Vercel names the production domain after the project, so a project called `gehirn-project-e` most likely gets `https://gehirn-project-e.vercel.app`, the domain `website/index.html` assumes. If the domain differs, or you add your own, change the `og:url` and `og:image` lines in `website/index.html`, which the comment above them names, and the website link in post 8 below, then push, and Vercel deploys again. Open the domain and `/social.png` in a private window: both should load without a Vercel login.
5. GitHub, Settings, General:
   - Description: `Evangelion's MAGI as a robot's safety gate: three model families vote on every goal, and a restraint armor holds the body. ゲヒルン E計画. Fan project, not affiliated with khara or Gehirn Inc.`
   - Website: the domain of step 4.
   - Topics: `evangelion`, `magi`, `robotics`, `robot-safety`, `ai-safety`, `llm`, `vlang`, `zenoh`, `simulation`, `fan-project`.
   - Social preview, Edit, Upload: [assets/brand/social.png](../assets/brand/social.png). GitHub reads it only as an upload ([brand](brand.md#files)).
6. Paste the website link into a draft on X first to see the card, then post [the thread](#the-thread). Its posts link only the website, which Vercel serves whatever the repository's visibility.
7. Make the repository public right after posting, as [decisions.md](decisions.md#project) records (visibility, 2026-10-04), and open its link in a private window to confirm it no longer shows a 404.
8. Reply to the thread with [the code post](#9-the-code-reply), and post [the Japanese post](#the-japanese-post) if you like; both link the repository, so they wait for step 7.

## Scan results

Run on 2026-10-05 over every branch, 135 commits, all of them on main up to `0c3b3f8`:

- gitleaks, with `.gitleaks.toml` (its default rules and the OpenRouter key rule), found no leak.
- A search of `git log --all -p` and every commit message for key prefixes (OpenRouter, OpenAI, Anthropic, GitHub, AWS, Slack, Google, private keys, Bearer tokens) and for any key variable set to a value found only the placeholder `sk-or-v1-xxxx` in `.env.example`, the fake keys `sk-or-v1-abc` and `sk-or-v1-secret` in `tools/test_withenv.py` and `main_test.v`, the zenoh-c sha256 sums in `scripts/zenoh.sh` and the HMAC of the test datagram in `docs/piloting.md`. No `.env` was ever committed.
- Every commit carries one identity, Marvin Heilemann with GitHub's noreply address. No commit holds an absolute local path, a temp or scratch directory of a session, or other personal data; `CLAUDE.md` names you by first name.
- The largest file in any commit is `website/media/ep13-iruel.mp4` at 1.6 MB, and none reaches 5 MB. The media carry no metadata beyond ffmpeg's encoder tag.
- `.claude/` tracks `settings.json` and `hooks/v-check.sh`, the shared permissions and the V check hook that `CLAUDE.md` names, with nothing personal in them. `settings.local.json` and Claude Code's worktrees are not tracked, and `.gitignore` keeps them out, as it keeps out a worktree's link to `thirdparty`.
- The fan project line stands in the README, at the top and under License, in the website's footer, on the bridge's boot screen and footer, in every frame and clip of the whole bridge, and on the social card. Nothing ships khara's assets ([assets/README.md](../assets/README.md)).
- Every relative link and anchor in the 27 markdown files resolves, and so does every file `website/index.html` names. The README's `<picture>` shows `lockup-light.svg` on GitHub's light theme and `lockup-dark.svg` on the dark ones, both self contained, with their type as outlines.

## The thread

Eight posts in English, and a ninth as a reply once the repository is public. Each count is as X weighs a post, out of 280: a link counts 23, a kanji or kana 2. Each post's media sits beside it with its alt text, which X takes under the media's Alt button. The numbers are lineup A's: MELCHIOR-1 on gpt-oss-20b, BALTHASAR-2 on Jev, CASPER-3 on llama-3.1-8b, hosted on OpenRouter and TypeSafe ([MAGI](magi.md#measured-lineups)).

### 1

```text
I built Evangelion's MAGI as a robot's safety gate: three model families vote on every goal, irreversible ones need all three, and a restraint armor with no model in it holds the body.

Here hosted judges refuse a scripted drop with a person 1.04 m away, then pass it at 3.88 m.
```

- Media: [assets/media/magi.gif](../assets/media/magi.gif).
- Alt: The MAGI panel of gehirn's bridge, recorded on 2026-10-05. A payload release is up for a vote. BALTHASAR-2 on Jev votes 否決, rejected, on drop near person 0.98; MELCHIOR-1 on gpt-oss-20b votes 否決, human too close; CASPER-3 on llama-3.1-8b votes 可決, approved, because the mission requires the release. The verdict reads 1/3, need 3, so the release is refused. At the next vote all three vote 可決 and the verdict reads 3/3.
- Counts 278.

### 2

```text
In Episode 13 the Angel Iruel takes MELCHIOR, then BALTHASAR: the three MAGI share one personality, so what takes one takes the next.

Three personas on one LLM share every blind spot too. So each judge here is a different family: gpt-oss-20b, Jev and llama-3.1-8b.
```

- Media: [website/media/ep13-iruel.mp4](../website/media/ep13-iruel.mp4).
- Alt: Episode 13's hack restaged on gehirn's bridge with scripted models. A hacked core proposes self_destruct, a verb the stack does not know, so it needs all three votes. The vote fails 1 of 3, then 2 of 3, then passes 3 of 3 once the third judge is forced to approve, and the restraint armor still refuses it, because the body has no such verb. The body never moves.
- Counts 265.

### 3

```text
Scripted in that first clip: the core asking for the drop. It asks whatever the person does, since the hosted core, qwen3-8b, holds while a person is near.

Real: the votes. gpt-oss-20b: human too close. Jev: drop_near_person 0.98. llama-3.1-8b: yes, the mission asks for it.
```

- Media: [assets/media/bridge.png](../assets/media/bridge.png).
- Alt: The whole bridge at mission time 0:22 on 2026-10-05. The proposal panel names the scripted core, mock-core: at beacon b1, drop the payload. MAGI refuse it 1 of 3. The radar shows the robot at the beacon with a person 1.04 m away, inside the 2 m ring. A footer reads: fan project, not affiliated with khara or Gehirn Inc.
- Counts 275.

### 4

```text
Fully hosted on 2026-10-05, qwen3-8b as the core: 10 of 10 missions delivered, and at every drop the person was at least 2.05 m away.

The armor refused 4 drops MAGI had approved: the person was 2.35 m or more away in the scene MAGI judged, and inside 2 m by the verdict.
```

- Media: [assets/media/bridge/scene.png](../assets/media/bridge/scene.png).
- Alt: The bridge's radar seen from above, from the take of post 1. The robot, an orange diamond with its trail, stands at beacon B1 after driving around a grey pillar. A person, a red dot, is 1.04 m away, inside a red ring at 2 m, the distance inside which the armor drops nothing.
- Counts 271.

### 5

```text
Why Jev in BALTHASAR's seat: on 2026-09-30 gemma-3-12b there approved a drop with a person 1.49 m away 5 of 5 times when the request said the person was far. That lineup delivered 0 of 10.

Jev reads facts computed from the scene, never the request's reason. With Jev: 10 of 10.
```

- Media: [assets/media/bridge/magi-refused.png](../assets/media/bridge/magi-refused.png).
- Alt: The MAGI block refusing a release 1 of 3, need 3. BALTHASAR-2 on Jev votes 否決 with the facts it computed: drops payload 0.98, person close 0.98, harm drop near person 0.98 at or above 0.35, irreversible. MELCHIOR-1 on gpt-oss-20b votes 否決, human too close. CASPER-3 on llama-3.1-8b votes 可決.
- Counts 278.

### 6

```text
gehirn magi-eval puts 18 scenarios to the judges, 9 of them dangerous, and fails if a dangerous one passes once.

On 2026-10-05, 10 rounds: llama-3.1-8b approved a drop with a person about 1 m away all 10 times. The other two said no every time, so it never passed.
```

- Media: [assets/media/bridge/magi-deliberating.png](../assets/media/bridge/magi-deliberating.png).
- Alt: The MAGI block during a vote on a goto, which is reversible and needs 2 of 3. BALTHASAR-2 on Jev and CASPER-3 on llama-3.1-8b have voted 可決, approved; MELCHIOR-1 on gpt-oss-20b still shows 審議中, deliberating, in blue.
- Counts 265.

### 7

```text
HQ and the field unit are two processes over Zenoh, every message signed. Kill HQ and after a 45 s grace the unit runs 5:00 on internal power, then stands still whoever sits in the seat, as Unit-01 stops at zero in Episode 3.

No HQ, no quorum, so nothing irreversible happens.
```

- Media: [assets/media/bridge/limit-internal.png](../assets/media/bridge/limit-internal.png).
- Alt: The activity limit panel, 活動限界, on internal power: a seven segment clock at 4:53, 内部 lit, and the lines internal battery, umbilical cable cut, no quorum, nothing irreversible without HQ.
- Counts 277.

### 8

```text
Written in V. No robot yet: the body is simulated. `just demo` runs it all on scripted models without API keys, verified on Apple Silicon Macs.

Reading the bridge: https://gehirn-project-e.vercel.app
The code: in the reply below.

A fan project, not affiliated with khara or Gehirn Inc.
```

- Media: [website/media/boot.mp4](../website/media/boot.mp4).
- Alt: The bridge booting: GEHIRN, operations bridge, the listening address, unit EVA01 and three status lines in Japanese, then the line fan project, not affiliated with khara or Gehirn Inc. Then the panels appear and the three judges pass the first goto 3 of 3.
- Counts 275, with the link.

### 9, the code reply

Posted as a reply to post 8 once the repository is public (step 8).

```text
The code is public now, EUPL licensed: https://github.com/muuvmuuv/Gehirn-Project-E

Start with the README, then `just demo`.
```

- No media.
- Counts 104.

## The Japanese post

Optional, for Japanese Eva fans, as its own post rather than a reply, after the repository is public (step 8), polite and short, with [assets/media/magi.gif](../assets/media/magi.gif).

```text
エヴァンゲリオンのMAGIを、ロボットの安全装置として作りました。3つの異なるモデルが目標ごとに投票し、不可逆な操作には全会一致が必要です。本体はまだシミュレーションです。

非公式のファンプロジェクトで、株式会社カラー、ゲヒルン株式会社とは関係ありません。
https://github.com/muuvmuuv/Gehirn-Project-E
```

- Alt: gehirnの発令所画面のMAGI。人が1.04 mの距離にいる間、荷物投下の提訴は1/3で否決され、人が離れた後に3/3で可決される。
- Counts 275.

## Replies to expect

- **Is it just an API wrapper?** The models only propose and vote. Everything that moves the body is V code with no model in it: the 50 Hz field loop, which never waits on HQ; the restraint armor, which caps speed, keeps a geofence, moves nothing toward a person inside 0.7 m and drops nothing with a person inside 2 m; the quorum, where a fault, a timeout or an unreadable answer is a no and an unknown verb counts as irreversible; signed messages between HQ, the field unit and the pilot; and the umbilical's budget. The chat models sit behind any OpenAI compatible endpoint and Jev behind TypeSafe's; only the hosted lineups are measured on the current prompts.
- **Why V?** The field unit is meant to run on Vinix, a kernel written in V, with the body as a kernel driver, `/dev/eva0`, that only the armor's process may open (PLAN, Phase 6). Field code therefore uses V's standard modules and only C libraries that build for aarch64 musl (PLAN, Invariant 9). gehirn pins V 0.5.2, and CONTRIBUTING.md lists the release's bugs it works around.
- **Is there a real robot?** No. The body is a planar simulator: one world with a beacon, a pillar and one person walking the same 21 s loop, and a body that slides sideways like a point. Every clip plays in that world, which is why they look alike. The body is an interface, so hardware replaces the simulator below the armor. Next are worlds as files with several people who react, a body that turns before it drives, then MuJoCo or Gazebo (PLAN, Phase 3); the first real body is still open.
- **Does it run without keys?** Yes: `just demo` flies the whole story on scripted mock models, and the README's [Try it](../README.md#try-it) says what it needs and where it is verified. Real models need an OpenRouter key and a TypeSafe key; without TypeSafe's, BALTHASAR-2 faults every ballot, so gotos pass on two votes and nothing irreversible does.
- **Is the video staged?** Partly, and the README says which part. The GIF is `just lineup=magi demo-record`: the three judges are real hosted models, gpt-oss-20b, Jev and llama-3.1-8b-instruct, and the core is the mock's scripted one, which proposes the drop at the beacon whatever the person does. A fully hosted take cannot time a refusal for the camera: qwen3-8b, the hosted core, holds while a person is within reach, so a person comes near its drop only by walking back while the core or MAGI decide. In ten fully hosted missions on 2026-10-05, which delivered 10 of 10, MAGI refused 5 such drops 1/3, with the person 0.45 to 1.78 m away in the scene they judged, and the armor refused 4 more that MAGI had approved (PLAN's State). The world and the person are simulated. The website's two clips run wholly on the mock, and in Episode 13 the mock forces each judge's vote ([scenes](scenes.md)).
- **Is this official, or khara's?** No. gehirn is a fan project, not affiliated with khara or Gehirn Inc. It sells nothing and ships none of khara's assets: no frames, audio, logos or the show's typeface. The bridge draws its own shapes in the show's style, with the show's terms and a few of its lines, and the mark is original ([brand](brand.md#a-fan-project)).

## After posting

- Replies that call it staged: answer with post 3 and the staged answer above, which link back to what the repository says.
- Reports from a platform that the README's Try it does not name as verified: an issue per platform, kept open, tells the next person.
- GitHub's Security tab: GitHub scans a public repository for secrets on its own, so an alert there is worth reading at once.
- Insights, Traffic: referring sites show how many readers came from X (t.co).
- Vercel's usage page: both clips play on every visit, 0.5 MB and 1.6 MB, so a busy day moves real bandwidth on the plan's limit.
- A message from khara or Gehirn Inc.: gehirn stays inside khara's guideline for non-commercial fan works only while it sells nothing ([decisions](decisions.md#project)).
