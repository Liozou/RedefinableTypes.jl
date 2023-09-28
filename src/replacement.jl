# Replace each self-referential occurence by the accurate new type

"""
    inplace_replace!(expr, pairs::Pair{Symbol,Symbol}...)

For each `old => new` pair in `pairs`, replace all occurences of the `old` symbol by `new`
in `expr`. Also return the modified `expr`.
"""
function inplace_replace!(expr, pairs::Pair{Symbol,Symbol}...)
    if expr isa Symbol
        for (initial, new) in pairs
            expr === initial && return new
        end
    elseif expr isa Expr
        for (i, arg) in enumerate(expr.args)
            if arg isa Symbol || arg isa Expr
                expr.args[i] = inplace_replace!(arg, pairs...)
            end
        end
    end
    return expr
end

function copy_replace(expr, pairs::Pair{Symbol,Symbol}...)
    if expr isa Symbol
        for (initial, new) in pairs
            expr === initial && return new
        end
    elseif expr isa Expr
        newargs = Vector{Any}(undef, length(expr.args))
        for (i, arg) in enumerate(expr.args)
            if arg isa Symbol || arg isa Expr
                newargs[i] = copy_replace(arg, pairs...)
            end
        end
        expr = makeexpr(expr.head, newargs)
    end
    return expr
end

function create_inner_new(core::TypeCore, sdef::StructDefinition, nparams, newname)
    name = typecore_to_expr(core)
    newcall = copy_replace(name, core.name=>:new)
    newinner = copy_replace(name, core.name=>newname)
    notypeargs, withtypesargs, _ = constructor_argument_list(sdef)
    resize!(notypeargs, nparams)
    resize!(withtypesargs, nparams)
    call = Expr(:where, Expr(:call, newinner, withtypesargs...), core.parameters...)
    value = Expr(:call, newcall, notypeargs...)
    Expr(:(=), call, value)
end

function make_stars(core::TypeCore, newname)
    stars = Vector{Expr}(undef, core.nparams+1)
    stars[end] = Expr(:(=), :(⋆(::Type{$(core.name)})), newname)
    curlyexpr = Expr(:curly, core.name)
    newexpr = Expr(:curly, newname)
    whereexpr = Expr(:where, Expr(:call, :⋆, Expr(:(::), Expr(:curly, :Type, curlyexpr))))
    for i in 1:core.nparams
        T = Symbol(:T, i)
        push!(curlyexpr.args, T)
        push!(newexpr.args, T)
        push!(whereexpr.args, T)
        stars[i] = Expr(:(=), deepcopy(whereexpr), deepcopy(newexpr))
    end
    stars
end

"""
    make_redefinable_declaration(decl::TypeDeclaration, mgs)

Main function: replace the input type declaration with a :block expression that contains
the modified type declarations.
"""
function make_redefinable_declaration(decl::TypeDeclaration, mgs)
    initial = decl.sig.core.name
    newname = mgs(initial)

    ret = Expr(:block)
    push!(ret.args, typedeclaration_to_expr(TypeDeclaration(decl.sig, 2, nothing)))

    newcore = TypeCore(newname, decl.sig.core.parameters, decl.sig.core.nparams)
    # the created abstract type has the initial name of the type
    newsupertype = typecore_to_expr(TypeCore(initial, get_type_parameters(decl.sig.core), decl.sig.core.nparams))
    newsig = TypeSignature(newcore, newsupertype)

    if decl.other isa StructDefinition
        newfields = Vector{Tuple{Symbol,Union{Symbol,Expr}}}(undef, length(decl.other.fields))
        for (i, (name, type)) in enumerate(decl.other.fields)
            newfields[i] = (name, inplace_replace!(type, initial=>newname))
        end

        newother = inplace_replace!(decl.other.other, initial=>newname)
        oldconstructors = [create_inner_new(decl.sig.core, decl.other, n, newname) for n in identify_news(decl.other.constructors, decl.sig.core)]

        newstruct = StructDefinition(newfields, oldconstructors, newother)
        push!(ret.args, typedeclaration_to_expr(TypeDeclaration(newsig, decl.flag, newstruct)))
        newconstructors = inplace_replace!.(decl.other.constructors, Ref(:new=>newname))
        append!(ret.args, newconstructors)
    else
        push!(ret.args, typedeclaration_to_expr(TypeDeclaration(newsig, decl.flag, nothing)))
    end

    getindex_expr = :(Base.getindex(::Type{$initial}, args...) = getindex($newname, args...))
    getindex_loc = functionloc(getindex, Tuple{Type, Vararg{Any}})
    getindex_expr.args[2].args[1] = LineNumberNode(Int(getindex_loc[2]), getindex_loc[1])
    push!(ret.args, getindex_expr)

    push!(ret.args, :(import RedefinableTypes: ⋆))
    append!(ret.args, make_stars(decl.sig.core, newname))
    push!(ret.args, nothing)

    ret
end
