using Statistics

using Oceananigans.Utils: work_layout
using Oceananigans.Fields
using Oceananigans.Operators: ℑxᶜᵃᵃ, ℑyᵃᶜᵃ, ℑzᵃᵃᶜ
using Oceananigans.Fields: AbstractReducedField, new_data
import Oceananigans.Fields: compute!

function subfilter_viscous_dissipation(model)

    u, v, w = model.velocities

    νₑ = model.diffusivities.νₑ

    Σˣˣ = ∂x(u)
    Σʸʸ = ∂y(v)
    Σᶻᶻ = ∂z(w)
    Σˣʸ = (∂y(u) + ∂x(v)) / 2
    Σˣᶻ = (∂z(u) + ∂x(w)) / 2
    Σʸᶻ = (∂z(v) + ∂y(w)) / 2

    ϵ = νₑ * 2 * ( Σˣˣ^2 + Σʸʸ^2 + Σᶻᶻ^2 + Σˣʸ^2 + Σˣᶻ^2 + Σʸᶻ^2 )

    return ϵ
end

"""
    turbulent_kinetic_energy_budget(model; b = BuoyancyField(model),
                                           w_scratch = ZFaceField(model.architecture, model.grid),
                                           c_scratch = CellField(model.architecture, model.grid))

Returns a `Dict` with `AveragedField`s correpsonding to terms in the turbulent kinetic energy budget.
The turbulent kinetic energy equation is

`` ∂_t E = - ∂_z ⟨w′e′ + w′p′⟩ - ⟨w′u′⟩ ∂_z U - ⟨w′v′⟩ ∂_z V + ⟨w′b′⟩ - ϵ ``,

where uppercase variables denote a horizontal mean, and primed variables denote deviations from
the horizontal mean.

The terms on the right side of the turbulent kinetic energy equation and their correpsonding keys are

1. `:advective_flux_divergence`, ``∂_z ⟨w′e′⟩``
2. `:pressure_flux_divergence`, ``∂_z ⟨w′p′⟩``
3. `:shear_production`, ``⟨w′u′⟩ ∂_z U``
4. `:buoyancy_flux`, ``⟨w′b′⟩``, where ``b`` is buoyancy
5. `:dissipation`, ``ϵ = ⟨2 νₑ Σᵢⱼ²⟩``, where ``νₑ`` is the subfilter eddy viscosity and ``Σᵢⱼ`` is the strain-rate tensor.

In addition, the return statistics `Dict` includes

6. `:advective_flux`, ``⟨w′e′⟩``
7. `:pressure_flux`, ``⟨w′p′⟩``
8. `:turbulent_kinetic_energy`, ``E = 1/2 (u′² + v′² + w′²)``

All variables are located at cell centers and share memory space with `c_scratch.data`, except `:advective_flux` and
`:pressure_flux`, which are located at `(Cell, Cell, Face)` and use `w_scratch`.

Note that these diagnostics do not compile on the GPU currently.
"""
function turbulent_kinetic_energy_budget(model;
                                         b = BuoyancyField(model),
                                         w_scratch = ZFaceField(model.architecture, model.grid),
                                         c_scratch = CellField(model.architecture, model.grid),
                                         U = AveragedField(model.velocities.u, dims=(1, 2)),
                                         V = AveragedField(model.velocities.v, dims=(1, 2)),
                                        )

    e = TurbulentKineticEnergy(model, U=U, V=V)
    shear_production = ShearProduction(model, data=c_scratch.data, U=U, V=V)

    u, v, w = model.velocities
    p = pressure(model)

    dissipation = subfilter_viscous_dissipation(model)
    advective_flux = w * e
    pressure_flux = w * p
    buoyancy_flux = @at (Cell, Cell, Cell) w * b

    advective_flux_divergence = ∂z(advective_flux)
    pressure_flux_divergence = ∂z(pressure_flux)

    turbulence_statistics = Dict()

    turbulence_statistics[:e] = AveragedField(e, dims=(1, 2))
    turbulence_statistics[:tke_shear_production]          = AveragedField(shear_production,          dims=(1, 2))
    turbulence_statistics[:tke_advective_flux]            = AveragedField(advective_flux,            dims=(1, 2))
    turbulence_statistics[:tke_pressure_flux]             = AveragedField(pressure_flux,             dims=(1, 2))
    turbulence_statistics[:tke_advective_flux_divergence] = AveragedField(advective_flux_divergence, dims=(1, 2))
    turbulence_statistics[:tke_pressure_flux_divergence]  = AveragedField(pressure_flux_divergence,  dims=(1, 2))
    turbulence_statistics[:tke_dissipation]               = AveragedField(dissipation,               dims=(1, 2))
    turbulence_statistics[:tke_buoyancy_flux]             = AveragedField(buoyancy_flux,             dims=(1, 2))

    return turbulence_statistics
end
