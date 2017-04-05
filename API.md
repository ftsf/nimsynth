Proposed Library API:

nsLoadPatch(filename): Patch
nsSavePatch(filename): bool

nsCreateMachine(machineClass, name): Machine
nsCreateMachineFromPatch(filename, name): Machine
nsDestroyMachine(machine)

nsConnectMachines(a,b, output, input)
nsDisconnectMachines(a,b, output, input)

nsGetInputs(machine): seq[Input]
nsGetOutputs(machine): seq[Output]
nsGetBindings(machine): seq[Binding]
nsGetParameters(machine): seq[Parameter]

nsBindParameter(a,b, binding, param): bool
nsUnbindParameter(a,b, binding, param): bool

nsSetParameterValue(machine: Machine, param: Parameter, value: float)
nsGetParameterValue(machine: Machine, param: Parameter): float

nsProcessAudio(nSamples: int, samples: pointer)
