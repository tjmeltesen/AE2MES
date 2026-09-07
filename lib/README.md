# Component and composition model

Hardware wrappers inherit from `BaseComponent`: `MeControllerComponent`,
`DatabaseComponent`, `RedstoneComponent`, `Machine`, `TransposerComponent`, and
`Interface`. Raw OpenComputers component calls belong in those wrappers; custom
hardware operations belong beside the wrapper that owns the device behavior.

`NodeComponent` composes the wrappers needed for one machine assignment.
`JobPool` constructs it on demand from the registry supplied by the cloud.
It does not inherit from `BaseComponent` because it represents a workflow,
not one OpenComputers address or proxy.
