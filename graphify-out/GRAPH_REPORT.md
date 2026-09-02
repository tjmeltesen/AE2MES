# Graph Report - AE2-ES2  (2026-08-30)

## Corpus Check
- 20 files · ~9,034 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 198 nodes · 225 edges · 6 communities detected
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 16 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 14|Community 14]]

## God Nodes (most connected - your core abstractions)
1. `JSON.encode()` - 8 edges
2. `errorAt()` - 6 edges
3. `Assignment.fromTable()` - 6 edges
4. `assertDeepEqual()` - 6 edges
5. `Runtime.new()` - 5 edges
6. `fail()` - 5 edges
7. `pass()` - 5 edges
8. `skipWhitespace()` - 4 edges
9. `parseObject()` - 4 edges
10. `JSON.decode()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `Comms:requestJSONPost()` --calls--> `JSON.encode()`  [INFERRED]
  lib\Comms.lua → lib\JSON.lua
- `JSON.decode()` --calls--> `roundTrip()`  [INFERRED]
  lib\JSON.lua → tests\test_json.lua
- `show()` --calls--> `JSON.encode()`  [INFERRED]
  tests\demo_run.lua → lib\JSON.lua
- `JSON.encode()` --calls--> `assertDeepEqual()`  [INFERRED]
  lib\JSON.lua → tests\test_json.lua
- `JSON.encode()` --calls--> `roundTrip()`  [INFERRED]
  lib\JSON.lua → tests\test_json.lua

## Communities

### Community 1 - "Community 1"
Cohesion: 0.11
Nodes (12): Assignment.fromJSON(), Assignment.fromTable(), Assignment.listFromJSON(), Registry.fromTable(), RouteStep.fromTable(), SequenceFlow.fromTable(), CloudClient:pollAssignment(), CloudClient:submitJobRequest() (+4 more)

### Community 2 - "Community 2"
Cohesion: 0.1
Nodes (3): Executor.new(), HardwareContext.fromRegistry(), JobPool:spawn()

### Community 4 - "Community 4"
Cohesion: 0.12
Nodes (5): Cache.new(), CloudClient.new(), JobPool.new(), NodeSensor.new(), Runtime.new()

### Community 6 - "Community 6"
Cohesion: 0.38
Nodes (10): encodeValue(), errorAt(), escapeString(), isArray(), JSON.decode(), parseArray(), parseNumber(), parseObject() (+2 more)

### Community 9 - "Community 9"
Cohesion: 0.5
Nodes (8): assertDeepEqual(), assertEqual(), assertThrows(), assertTrue(), deepEqual(), fail(), pass(), roundTrip()

### Community 14 - "Community 14"
Cohesion: 0.6
Nodes (4): checkModule(), checkSyntax(), issue(), ok()

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `JSON.encode()` connect `Community 1` to `Community 9`, `Community 6`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `JSON.encode()` (e.g. with `Comms:requestJSONPost()` and `CloudClient:submitJobRequest()`) actually correct?**
  _`JSON.encode()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `Runtime.new()` (e.g. with `Cache.new()` and `CloudClient.new()`) actually correct?**
  _`Runtime.new()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.11 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._