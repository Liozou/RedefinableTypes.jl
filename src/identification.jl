# For each type declaration, identify the subexpression to be replaced by type parameters

function get_root_symbol(@nospecialize(x))
    x isa Symbol && return x
    if x isa Expr
        if x.head === :curly || x.head === :where || x.head === :call
            return get_root_symbol(x.args[1])
        end
    end
    nothing
end

function get_type_parameters(x)
    list = x isa TypeCore ? x.parameters : @view x.args[2:end]
    ret = Vector{Symbol}(undef, length(list))
    for (i, p) in enumerate(list)
        if p isa Symbol
            ret[i] = p
        else
            if p.head === :<: || p.head === :>:
                ret[i] = p.args[1]
            else
                if p.head !== :comparison || !(p.args[2] == p.args[4] == :<:)
                    throw(MalformedExprError(Symbol("type parameter"), p))
                end
                ret[i] = p.args[3]
            end
        end
    end
    ret
end


function unshadowed_symbols!(encountered_symbols, @nospecialize(expr), shadowed_symbol=Set{Symbol}())
    if expr isa Symbol && expr ∉ shadowed_symbol
        push!(encountered_symbols, expr)
    elseif expr isa Expr
        if expr.head !== :where
            for arg in expr.args
                unshadowed_symbols!(encountered_symbols, arg, shadowed_symbol)
            end
        else
            new_shadowed_symbol = copy(shadowed_symbol)
            for i in 2:length(expr.args)
                arg = expr.args[i]
                if arg isa Symbol
                    push!(new_shadowed_symbol, arg)
                elseif arg isa Expr
                    if arg.head === :<: || arg.head === :>:
                        unshadowed_symbols!(encountered_symbols, arg.args[2], new_shadowed_symbol)
                        push!(new_shadowed_symbol, arg.args[1])
                    else
                        if p.head !== :comparison || !(p.args[2] == p.args[4] == :<:)
                            throw(MalformedExprError(Symbol("type parameter"), p))
                        end
                        unshadowed_symbols!(encountered_symbols, arg.args[1], new_shadowed_symbol)
                        unshadowed_symbols!(encountered_symbols, arg.args[5], new_shadowed_symbol)
                        push!(new_shadowed_symbol, arg.args[3])
                    end
                end
            end
            new_encountered_symbols = Set{Symbol}()
            unshadowed_symbols!(new_encountered_symbols, expr.args[1], new_shadowed_symbol)
            union!(encountered_symbols, new_encountered_symbols)
        end
    end
    nothing
end


function alltypesinferrable(core::TypeCore, sdef::StructDefinition)
    encountered_types = Set{Symbol}()
    for (_, type) in sdef.fields
        unshadowed_symbols!(encountered_types, type)
    end
    issubset(get_type_parameters(core), encountered_types)
end

function _identify_news!(numbers, expr::Expr)
    if expr.head === :call && get_root_symbol(expr.args[1]) === :new
        push!(numbers, length(expr.args) - 1)
    else
        for arg in expr.args
            arg isa Expr && _identify_news!(numbers, arg)
        end
    end
    nothing
end

"""
    identify_news(constructors::Vector{Expr}, core::TypeCore)

Return the list of possible argument numbers given to `new{...}` calls in the constructors.
"""
function identify_news(constructors::Vector{Expr}, core::TypeCore)
    isempty(constructors) && return [core.nparams]
    numbers = BitSet()
    for constructor in constructors
        _identify_news!(numbers, constructor)
    end
    return collect(numbers)
end
