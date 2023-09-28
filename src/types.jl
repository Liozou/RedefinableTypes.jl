"""
    TypeCore

Core of the definition of a type, consisting of three fields:
- `name::Symbol`: the name of the type.
- `parameters::Vector{Union{Symbol,Expr}}`: its parameters. Each parameter can be either a
  `Symbol`, which is its name, or an `Expr` which can be of the form `T<:Foo`, `T>:Bar` or
  `Bar<:T<:Foo` where `T` is the actual type parameter.
- `nparams`: the input number of parameters, i.e. the initial length of `parameters`.
"""
struct TypeCore
    name::Symbol
    parameters::Vector{Union{Symbol,Expr}}
    nparams::Int
end

function tryTypeCore(@nospecialize ex1)
    ex1 isa Symbol && return TypeCore(ex1, Union{Symbol,Expr}[], 0)
    Meta.isexpr(ex1, :curly) && return TypeCore(ex1.args[1], ex1.args[2:end], length(ex1.args)-1)
    nothing
end

function typecore_to_expr(t::TypeCore)
    isempty(t.parameters) && return t.name
    return Expr(:curly, t.name, t.parameters...)
end
Base.show(io::IO, t::TypeCore) = show(io, typecore_to_expr(t))

"""
    TypeSignature

Signature of a type, consisting of:
- `core::TypeCore` its type core, i.e. its name and parameters.
- `supertype::Union{Symbol,Expr}` its supertype.
"""
struct TypeSignature
    core::TypeCore
    supertype::Union{Symbol,Expr}
end

function tryTypeSignature(@nospecialize ex1)
    core = tryTypeCore(ex1)
    core isa TypeCore && return TypeSignature(core, :Any)
    Meta.isexpr(ex1, :<:) || return nothing
    ex1::Expr
    core = tryTypeCore(ex1.args[1])
    core isa TypeCore && return TypeSignature(core, ex1.args[2])
    nothing
end

function typesignature_to_expr(t::TypeSignature)
    core = typecore_to_expr(t.core)
    t.supertype === :Any && return core
    return Expr(:<:, core, t.supertype)
end
Base.show(io::IO, t::TypeSignature) = show(io, typesignature_to_expr(t))

"""
    StructDefinition

Container for the content of a `struct`. Consists in:
- `fields::Vector{Tuple{Symbol,Union{Symbol,Expr}}}` the list of fields. Each pair
  `(name, type)` consists in the `name` of the field and its `type`.
- `constructors::Vector{Expr}` a list of inner constructor declarations.
- `other::Expr` a block of other declarations inside the struct.
  Internal blocks are expanded, so that there is no block in the
  arguments of `other`.
"""
struct StructDefinition
    fields::Vector{Tuple{Symbol,Union{Symbol,Expr}}}
    constructors::Vector{Expr}
    other::Expr
end

function add_field!(fields, other, constructors, @nospecialize(arg), name)
    if arg isa Expr
        if arg.head === :(::)
            push!(fields, (arg.args[1], arg.args[2]))
        elseif arg.head === :block
            for subarg in arg.args
                add_field!(fields, other, constructors, subarg, name)
            end
        elseif arg.head === :function || (arg.head === :(=) && arg.args[1] isa Expr &&
               (arg.args[1].head === :call || (arg.args[1].head === :where && Meta.isexpr(arg.args[1].args[1], :call))))
            symb = get_root_symbol(arg.args[1].args[1])
            if symb === name
                push!(constructors, arg)
            else
                push!(other, arg)
            end
        else
            push!(other, arg)
        end
    elseif arg isa Symbol
        push!(fields, (arg, :Any))
    else
        push!(other, arg)
    end
    nothing
end

function StructDefinition(expr::Expr, core::TypeCore)
    expr.head === :block || throw(MalformedExprError(:struct, expr))
    fields = Tuple{Symbol,Union{Symbol,Expr}}[]
    other = Expr(:block)
    constructors = Expr[]
    add_field!(fields, other.args, constructors, expr, core.name)
    sdef = StructDefinition(fields, constructors, other)
    if isempty(constructors)
        name = typecore_to_expr(core)
        newcall = copy_replace(name, core.name=>:new)
        notypeargs, withtypesargs, convertargs = constructor_argument_list(sdef)
        if alltypesinferrable(core, sdef)
            callwithtypes = if isempty(core.parameters)
                Expr(:call, core.name, withtypesargs...)
            else
                Expr(:where, Expr(:call, core.name, withtypesargs...), core.parameters...)
            end
            valuewithtypes = Expr(:call, newcall, notypeargs...)
            push!(sdef.constructors, Expr(:(=), callwithtypes, valuewithtypes))
        end
        callnotypes = if isempty(core.parameters)
            Expr(:call, Expr(:(::), Expr(:curly, :Type, name)), notypeargs...)
        else
            Expr(:call, Expr(:(::), Expr(:where, Expr(:curly, :Type, name), core.parameters...)), notypeargs...)
        end
        valuenotypes = Expr(:call, newcall, convertargs...)
        push!(sdef.constructors, Expr(:(=), callnotypes, valuenotypes))
    end
    sdef
end

function constructor_argument_list(sdef::StructDefinition)
    notype = Symbol[]
    withtypes = Expr[]
    converts = Expr[]
    for (name, type) in sdef.fields
        push!(notype, name)
        push!(withtypes, Expr(:(::), name, type))
        push!(converts, Expr(:call, :convert, type, name))
    end
    notype, withtypes, converts
end

function structdefinition_to_expr(sdef::StructDefinition)
    arg1 = get(sdef.other.args, 1, nothing)
    block = arg1 isa LineNumberNode ? Expr(:block, arg1) : Expr(:block)
    append!(block.args, Expr(:(::), field, type) for (field, type) in sdef.fields)
    append!(block.args, arg1 isa LineNumberNode ? (@view sdef.other.args[2:end]) : x.other.args)
    append!(block.args, sdef.constructors)
    block
end
structdefinition_to_expr(::Nothing) = Expr(:block)

"""
    TypeDeclaration

Description of a type declaration. Consists in
- `sig::TypeSignature`: the signature, including the name, the type parameters and the
  supertype
- `flag::Int`: if the type is declared as `primitive`, `flag` is minus the declared size.
  If it is defined as a `mutable struct`, `flag` is 1. If an `abstract type`, `flag` is 2.
  Otherwise, `flag` is 0.
- `other`: if the type is declared as a `struct`, contain the `StructDefinition`.
  Otherwise, contains `nothing`.
"""
struct TypeDeclaration
    sig::TypeSignature
    flag::Int # minus the size for primitive type, 1 for mutable, 2 for abstract, 0 otherwise
    other::Union{Nothing,StructDefinition} # fields and constructors for structs
end

function TypeDeclaration(ex0::Expr)
    if ex0.head === :struct
        sig0::TypeSignature = tryTypeSignature(ex0.args[2])
        return TypeDeclaration(sig0, ex0.args[1], StructDefinition(ex0.args[3], sig0.core))
    end
    sig::TypeSignature = tryTypeSignature(ex0.args[1])
    ex0.head === :abstract && return TypeDeclaration(sig, 2, nothing)
    @assert ex0.head === :primitive
    return TypeDeclaration(sig, -ex0.args[2]::Int, nothing)
end

function typedeclaration_to_expr(t::TypeDeclaration)
    signature = typesignature_to_expr(t.sig)
    t.flag < 0 && return Expr(:primitive, signature, -t.flag)
    t.flag == 2 && return Expr(:abstract, signature)
    return Expr(:struct, Bool(t.flag), signature, structdefinition_to_expr(t.other))
end
Base.show(io::IO, t::TypeDeclaration) = show(io, typedeclaration_to_expr(t))


# """
#     TypeAlias

# Struct representing a type alias declaration. Consists in
# - `isconst::Bool`: true if the alias was declared with the `const` keyword.
# - `core::TypeCore`: the name and declared type parameters.
# - `aliasof::Union{Symbol,Expr}`: the definition of the alias.
# """
# struct TypeAlias
#     isconst::Bool
#     core::TypeCore
#     aliasof::Union{Symbol,Expr}
# end

# function tryTypeAlias(ex0::Expr)
#     isconst, ex1 = ex0.head === :const ? (true, ex0.args[1]) : (false, ex0)
#     Meta.isexpr(ex1, :(=)) || return nothing
#     ex1::Expr
#     core = tryTypeCore(ex1.args[1])
#     core isa TypeCore || return nothing
#     isconst || (PRINT_WARNING::Bool && @warn "Type alias $core should be explicitly declared as `const` and will be treated as such.")
#     aliasof = ex1.args[2]
#     aliasof isa Symbol && return TypeAlias(isconst, core, aliasof)
#     Meta.isexpr(aliasof, :curly) || Meta.isexpr(aliasof, :where) || return nothing
#     return TypeAlias(isconst, core, aliasof)
# end

# function typealias_to_expr(t::TypeAlias)
#     expr = Expr(:(=), typecore_to_expr(t.core), t.aliasof)
#     return t.isconst ? Expr(:const, expr) : expr
# end
# Base.show(io::IO, t::TypeAlias) = show(io, typealias_to_expr(t))


TypeCore(x::TypeDeclaration) = x.sig.core
# TypeCore(x::TypeAlias) = x.core
