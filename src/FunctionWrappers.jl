#!/usr/bin/julia

__precompile__(true)

module FunctionWrappers

using Compat

# Used to bypass NULL check
@inline function assume(v::Bool)
    Base.llvmcall(("declare void @llvm.assume(i1)",
                   """
                   %v = trunc i8 %0 to i1
                   call void @llvm.assume(i1 %v)
                   ret void
                   """), Cvoid, Tuple{Bool}, v)
end

Base.@pure is_singleton(@nospecialize(T)) = isdefined(T, :instance)
# Base.@pure get_instance(@nospecialize(T)) = Base.getfield(T, :instance)

@inline function convert_ret(::Type{Ret}, ret) where Ret
    # Only treat `Cvoid` as ignoring return value.
    # Treating all singleton as ignoring return value is also possible as shown in the
    # commented out implementation but it doesn't seem necessary.
    # The stricter rule may help catching errors and can be more easily changed later.
    Ret === Cvoid && return
    # is_singleton(Ret) && return get_instance(Ret)
    return convert(Ret, ret)
end

# Call wrapper since `cfunction` does not support non-function
# or closures
struct CallWrapper{Ret} <: Function end
(::CallWrapper{Ret})(f, args...) where Ret = convert_ret(Ret, f(args...))

# Specialized wrapper for
for nargs in 0:128
    @eval (::CallWrapper{Ret})(f, $((Symbol("arg", i) for i in 1:nargs)...)) where {Ret} =
        convert_ret(Ret, f($((Symbol("arg", i) for i in 1:nargs)...)))
end

# Convert return type and generates cfunction signatures
Base.@pure map_rettype(T) =
    (isbitstype(T) || T === Any || is_singleton(T)) ? T : Ref{T}
Base.@pure function map_cfunc_argtype(T)
    if is_singleton(T)
        return Ref{T}
    end
    return (isbitstype(T) || T === Any) ? T : Ref{T}
end
Base.@pure function map_argtype(T)
    if is_singleton(T)
        return Any
    end
    return (isbitstype(T) || T === Any) ? T : Any
end
Base.@pure get_cfunc_argtype(Obj, Args) =
    Tuple{Ref{Obj}, (map_cfunc_argtype(Arg) for Arg in Args.parameters)...}

if isdefined(Base, Symbol("@cfunction"))
    @generated function gen_fptr(::Type{Ret}, ::Type{Args}, ::Type{objT}) where {Ret,Args,objT}
        quote
            @cfunction($(CallWrapper{Ret}()), $(map_rettype(Ret)),
                       ($(get_cfunc_argtype(objT, Args).parameters...),))
        end
    end
else
    function gen_fptr(::Type{Ret}, ::Type{Args}, ::Type{objT}) where {Ret,Args,objT}
        cfunction(CallWrapper{Ret}(), map_rettype(Ret), get_cfunc_argtype(objT, Args))
    end
end

mutable struct FunctionWrapper{Ret,Args<:Tuple}
    ptr::Ptr{Cvoid}
    objptr::Ptr{Cvoid}
    obj
    objT
    function (::Type{FunctionWrapper{Ret,Args}})(obj::objT) where {Ret,Args,objT}
        objref = Base.cconvert(Ref{objT}, obj)
        new{Ret,Args}(gen_fptr(Ret, Args, objT),
                      Base.unsafe_convert(Ref{objT}, objref), objref, objT)
    end
    (::Type{FunctionWrapper{Ret,Args}})(obj::FunctionWrapper{Ret,Args}) where {Ret,Args} = obj
end

Base.convert(::Type{T}, obj) where {T<:FunctionWrapper} = T(obj)
Base.convert(::Type{T}, obj::T) where {T<:FunctionWrapper} = obj

@noinline function reinit_wrapper(f::FunctionWrapper{Ret,Args}) where {Ret,Args}
    objref = f.obj
    objT = f.objT
    ptr = gen_fptr(Ret, Args, objT)::Ptr{Cvoid}
    f.ptr = ptr
    f.objptr = Base.unsafe_convert(Ref{objT}, objref)
    return ptr
end

@generated function do_ccall(f::FunctionWrapper{Ret,Args}, args) where {Ret,Args}
    # Has to be generated since the arguments type of `ccall` does not allow
    # anything other than tuple (i.e. `@pure` function doesn't work).
    quote
        $(Expr(:meta, :inline))
        ptr = f.ptr
        if ptr == C_NULL
            # For precompile support
            ptr = reinit_wrapper(f)
        end
        assume(ptr != C_NULL)
        objptr = f.objptr
        ccall(ptr, $(map_rettype(Ret)),
              (Ptr{Cvoid}, $((map_argtype(Arg) for Arg in Args.parameters)...)),
              objptr, $((:(convert($(Args.parameters[i]), args[$i]))
                         for i in 1:length(Args.parameters))...))
    end
end

@inline (f::FunctionWrapper)(args...) = do_ccall(f, args)

# Testing only
const identityAnyAny = FunctionWrapper{Any,Tuple{Any}}(identity)

end
