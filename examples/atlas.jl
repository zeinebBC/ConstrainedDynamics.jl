using ConstrainedDynamics
using ConstrainedDynamicsVis


path = "examples/examples_files/atlas_simple.urdf"
mech, shapes = Mechanism(path, floating=false, g = -.5)

storage = simulate!(mech, 10., record = true)
visualize(mech, storage, shapes)
