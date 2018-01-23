mutable struct RHS_IIF_Scalar{F,uType,tType,aType,P} <: Function
  f::F
  tmp::uType
  t::tType
  dt::tType
  a::aType
  p::P
end

function (f::RHS_IIF_Scalar)(u,resid)
  resid[1] = first(u) - f.tmp - (f.a*f.dt)*first(f.f.f2(first(u),f.p,f.t+f.dt,))
end

function initialize!(integrator,cache::Union{GenericIIF1ConstantCache,GenericIIF2ConstantCache})
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(integrator.kshortsize)
  A = integrator.f.f1
  cache.uhold[1] = integrator.f.f2(integrator.uprev,integrator.p,integrator.t)
  integrator.fsalfirst = integrator.f.f1(integrator.uprev,integrator.p,integrator.t) .+ cache.uhold[1]

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsalfirst
end

function perform_step!(integrator,cache::Union{GenericIIF1ConstantCache,GenericIIF2ConstantCache},repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uhold,rhs,nl_rhs = cache

  # If adaptive, this should be computed after and cached
  A = integrator.f.f1
  if typeof(cache) <: GenericIIF1ConstantCache
    rhs.tmp = expm(A*dt)*(uprev)
  elseif typeof(cache) <: GenericIIF2ConstantCache
    @muladd rhs.tmp = expm(A*dt)*(uprev + 0.5dt*uhold[1]) # This uhold only works for non-adaptive
  end

  if integrator.success_iter > 0 && !integrator.reeval_fsal
    uhold[1] = current_extrapolant(t+dt,integrator)
  end # else uhold is previous value.

  rhs.t = t
  rhs.dt = dt
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  uhold[1] = integrator.f.f2(nlres[1],integrator.p,t+dt)
  u = nlres[1]
  integrator.fsallast = A*u + uhold[1]
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

mutable struct RHS_IIF{F,uType,tType,aType,DiffCacheType,P} <: Function
  f::F
  tmp::uType
  t::tType
  dt::tType
  a::aType
  dual_cache::DiffCacheType
  p::P
end
function (f::RHS_IIF)(u,resid)
  du = get_du(f.dual_cache, eltype(u))
  f.f.f2(du,u,f.p,f.t+f.dt)
  @. resid = u - f.tmp - (f.a*f.dt)*du
end

function initialize!(integrator,cache::Union{GenericIIF1Cache,GenericIIF2Cache})
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  A = integrator.f.f1
  integrator.f.f2(cache.rtmp1,integrator.uprev,integrator.p,integrator.t)
  A_mul_B!(cache.k,A,integrator.uprev)
  @. integrator.fsalfirst = cache.k + cache.rtmp1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::Union{GenericIIF1Cache,GenericIIF2Cache},repeat_step=false)
  @unpack rtmp1,tmp,k = cache
  @unpack rhs,nl_rhs = cache
  @unpack t,dt,uprev,u,f,p = integrator

  @. k = uprev
  if typeof(cache) <: GenericIIF2Cache
    @muladd @. k = k + 0.5dt*rtmp1
  end

  A_mul_B!(tmp,cache.expA,k)

  if integrator.success_iter > 0 && !integrator.reeval_fsal
    current_extrapolant!(u,t+dt,integrator)
  end # else uhold is previous value.

  rhs.t = t
  rhs.dt = dt
  nlres = integrator.alg.nlsolve(nl_rhs,u)

  copy!(u,nlres)
  integrator.f.f2(rtmp1,nlres,integrator.p,t+dt)
  A = f.f1
  integrator.fsallast .= A*u .+ rtmp1
end
