# # PRINT_WARNING definition

# @static if VERSION >= v"1.8-"
#     PRINT_WARNING::Bool = true
# else
#     PRINT_WARNING = true
# end

# """
#     PRINT_WARNING

# Explicitly set it to `false` to suppress warnings from RecursiveTypes.jl, or to `true` to
# revert to the default behavior of showing them.

# ## Example
# ```jldocstring
# julia> using RecursiveTypes

# julia> RecursiveTypes.PRINT_WARNING = false
# false

# julia> @recursive_types begin
#     uAB{T} = Union{A,B{T}}
#     struct A <: AbstractVector{B}
#         x::B{A}
#     end
#     struct B{T} <: AbstractVector{uAB{A}} end
# end;

# julia> RecursiveTypes.PRINT_WARNING = true
# true

# julia> @recursive_types begin
#     uAB{T} = Union{A,B{T}}
#     struct A <: AbstractVector{B{A}}
#         x::B{A}
#     end
#     struct B{T} <: AbstractVector{uAB{A}} end
# end;
# ┌ Warning: Type alias uAB should be explicitly declared as `const` and will be treated as such.
# └ @ Main REPL[0]:0
# ┌ Warning: In definition of A, type A used within parameters of posterior type B will be replaced by Any.
# └ @ Main REPL[0]:0
# ```
# """
# PRINT_WARNING


# ModGenSym

struct ModGenSym <: Function
    mod::Symbol
    x::Base.RefValue{Int}
    typevars::IdDict{Symbol,Union{Symbol,Expr}}
end
const globalmgsref = IdDict{Symbol,ModGenSym}()
function ModGenSym(x::Symbol)
    mgs = get!(() -> ModGenSym(x, Ref(0), IdDict{Symbol,Union{Symbol,Expr}}()), globalmgsref, x)
    empty!(mgs.typevars)
    mgs
end
(mgs::ModGenSym)() = Symbol('#', mgs.mod, "##", mgs.x[] += 1)
(mgs::ModGenSym)(x::Symbol) = Symbol('#', mgs.mod, "#_", x, "_##", mgs.x[] += 1)
Base.setindex!(mgs::ModGenSym, x, T::Symbol) = setindex!(mgs.typevars, x, T)
Base.getindex(mgs::ModGenSym, T::Symbol) = get(mgs.typevars, T, T)

struct ModGenSymNamed <: Function
    mgs::ModGenSym
    name::Symbol
end
function (mgsn::ModGenSymNamed)()
    mgsn.mgs(mgsn.name)
end

# Other

function makeexpr(head, args)
    x = Expr(head)
    x.args = args
    return x
end

@static if isdefined(Base, :remove_linenums!)
    using Base: remove_linenums!
else
    # from Base
    function remove_linenums!(ex::Expr)
        if ex.head === :block || ex.head === :quote
            filter!(ex.args) do x
                isa(x, Expr) && x.head === :line && return false
                isa(x, LineNumberNode) && return false
                return true
            end
        end
        for subex in ex.args
            subex isa Expr && remove_linenums!(subex)
        end
        return ex
    end
end
