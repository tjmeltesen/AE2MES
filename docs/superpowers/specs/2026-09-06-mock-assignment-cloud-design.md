# Mock Assignment Cloud Mode — Design

**Date:** 2026-09-06  
**Status:** Approved  
**Scope:** In-game OpenComputers full pipeline with real hardware; cloud HTTP replaced by a local JSON fixture when enabled.

## Goal

Run the normal `main.lua` → Runtime → JobPool → NodeComponent loop on real OC hardware without a live cloud server. Assignments come from a JSON file; status and completion are printed locally.

## Non-goals

- Fully mocked PC/Docker hardware simulation for this feature
- Separate `MockCloudClient` module or alternate `main_mock.lua` entrypoint
- Changing JobPool / NodeComponent execution semantics
- Hand-authoring recipe items/fluids in the fixture for each test run

## Configuration

Extend Runtime / CloudClient config (set in `src/main.lua`):

| Field | Type | Purpose |
|-------|------|---------|
| `useMockAssignment` | boolean | When true, CloudClient skips HTTP for request/status/completion |
| `mockAssignmentPath` | string | Path to fixture JSON (default `fixtures/mock_assignment.json`) |

Existing fields (`nodeId`, `cloudBaseUrl`, ME/machine settings) remain. `cloudBaseUrl` is unused while mock mode is on.

## Fixture

New file: `fixtures/mock_assignment.json`

- Schema v1 assignment shape (same as production cloud payload)
- Author **registry addresses**, **sides**, and **steps** for the physical test machine
- `sequenceFlow.items` / `fluids` may be empty or omitted; mock mode overwrites them at request time
- Supported steps remain JobPool’s existing methods (`transferToMachine`, `waitForProcess` / `isDone` polling, etc.)

## CloudClient behavior

When `useMockAssignment` is true:

| Method | Behavior |
|--------|----------|
| `submitJobRequest(request)` | Read file at `mockAssignmentPath`. Decode JSON. Ensure `sequenceFlow` exists. Set `items`/`fluids` from `request.buffer` (map buffer item `size`→assignment `count` as needed). Parse with existing Assignment helpers. Return assignment list. No HTTP. |
| `reportStatus(snapshot)` | Print a short local summary; return `true` |
| `reportCompletion(jobId, result)` | Print jobId + result summary; return `true` so Runtime can remove the run |
| `pollAssignment(jobId)` | Read/parse the same fixture (or return that assignment if id matches); no HTTP |

When `useMockAssignment` is false: existing HTTP behavior unchanged.

File read / JSON / Assignment parse failures return `nil, error` like transport failures so Runtime keeps the pending request for retry.

## Startup kick

While mock mode is on, force **one** pending job request at Runtime startup so the first tick can submit without waiting for an ME buffer signature change. Subsequent requests continue to follow NodeSensor’s normal pending/cooldown rules.

## Unchanged collaborators

- **Runtime:** still builds the job request (buffer + machines + activeJobs), submits via CloudClient, spawns into JobPool, reports completion
- **JobPool:** parse → configureFromRegistry → tick steps → completion metrics
- **NodeComponent:** hardware only
- **NodeSensor:** buffer watch and machine scan (still used for request payload and dynamic items/fluids)

## In-game usage

1. Edit `fixtures/mock_assignment.json` with real component addresses and sides
2. Set `useMockAssignment = true` (and path if needed) in `main.lua`
3. Copy `src/`, `lib/`, and `fixtures/` onto the OC computer
4. Run `main.lua`
5. Watch local prints for request load, job progress, and completion; real hardware executes transfers

## Testing

- Unit: CloudClient mock path loads fixture, injects buffer items/fluids, skips HTTP; status/completion return ok
- Manual: in-game run with mock flag and fixture matching one physical node

## Out of scope follow-ups

- Optional `mockCloudReports` split (status/completion still hitting real cloud) — not required for this design
- Updating the older `features/fixtures/cloud_assignment.json` schema (separate concern)
