using Rotations
using Plots: RGBA
using StaticArrays

using ConstrainedDynamics

# Parameters
joint_axis = [1.0;0.0;0.0]

length1 = 0.5
width, depth = 0.5, 0.5
box1 = Box(width, depth, length1, 1., color = RGBA(1., 1., 0.))


# Links
origin = Origin{Float64}()

link1 = Body(box1)
links = [link1]

# Constraints
cf = 0.1
joint1 = InequalityConstraint(Friction(link1, [0;0;1.0], cf))
ineqcs = [joint1]

joint0to1 = EqualityConstraint(OriginConnection(origin, link1))
eqcs = [joint0to1]

shapes = [box1]


mech = Mechanism(origin, links, eqcs, ineqcs, shapes = shapes, tend=20.)

setPosition!(mech,link1,x=[0;0;0.])
setVelocity!(mech,link1,v = [0;2.;0])
setForce!(mech,link1,F=[0;0.;0.])


simulate!(mech,save = true)
visualize!(mech)
