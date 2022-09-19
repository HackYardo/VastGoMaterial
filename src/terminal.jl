#import JSON3  
    # JSON3.read(), JSON3.write(), JSON3.pretty()
include("utility.jl")  
    # match_diy(), split_undo()

struct Bot 
  dir::String 
  cmd::String
end

mutable struct BotSet
  dict::Dict{String, Bot}
  default::Vector{String}
end 

function Base.convert(::Type{Bot}, t::NamedTuple)
    Bot(t.dir, t.cmd)
end 
function Base.convert(::Type{Bot}, t::Tuple)
    Bot(t[1], t[2])
end 
function Base.convert(::Type{Bot}, d::Dict)
    Bot(d["dir"], d["cmd"])
end 
function Base.convert(::Type{Bot}, v::Vector)
    Bot(v[1], v[2])
end 

function bot_config()
    include_string(Main, readchomp("data/config.txt"))
    return botDefault, botDict
end

function bot_get()
    botDefault, botDict = bot_config()
    botSet = BotSet(botDict, botDefault)
    
    botToRun = String[]
    if length(ARGS) == 0 
        botToRun = botDefault
    else
        botToRun = ARGS
    end
    
    botSet
end 

function bot_ready(proc::Base.Process)
    query(proc, "!")
    outInfo = reply(proc)
    
    if outInfo[1] != '?'
        errInfo = reply(proc.err)
        @info "stdout:\n$outInfo"
        @info "stderr:\n$errInfo"
        @error "Please look at the above ↑↑↑"
        exit()
    end

    #println("$proc")
end

#=
Why Base.PipeEndpoint() && run() or why not open()?
Because stderr is hard to talk with, source:
https://discourse.julialang.org/t/avoiding-readavailable-when-communicating-
with-long-lived-external-program/61611/25
=#
function bot_run(; dir="", cmd="")::Base.Process
    inp = Base.PipeEndpoint()
    out = Base.PipeEndpoint()
    err = Base.PipeEndpoint()
    
    cmdVector = split(cmd) # otherwise there will be ' in command
    command = Cmd(`$cmdVector`, dir=dir)
    print("VastGo will run the command: ")
    printstyled("$cmd\n", color=6)
    print("in the directory: ")
    printstyled("$dir\n", color=6)
    #println(command)

    process = run(command,inp,out,err;wait=false)
    bot_ready(process)
    
    return process
end

function bot_end(proc::Base.Process)
    println(reply(proc))
    close(proc)
end

function gtp_valid(sentence::String)::Bool
    if "" in split(sentence, keepempty=true)
        return false
    else 
        return true
    end 
end 

query((proc, sentence)) = query(proc, sentence)
function query(proc::Base.Process, sentence::String)
    println(proc, sentence)
end

function reply(proc::Union{Base.Process, Base.PipeEndpoint})
    paragraph = readuntil(proc, "\n\n")
    return "$paragraph\n"
end

function name_get(proc::Base.Process)
    query(proc, "name")
    reply(proc)[3:end-1]
end

function version_get(proc::Base.Process)
    query(proc, "version")
    reply(proc)[3:end-1]
end 

function gtp_startup_info(proc::Base.Process)
    name = name_get(proc)
    if name == "Leela Zero"
        println(readuntil(proc.err, "MiB.", keep=true))
    elseif name == "KataGo"
        println(readuntil(proc.err, "loop", keep=true))
    else
    end
end 

function gtp_ready(proc::Base.Process)
    gtp_startup_info(proc)
    printstyled("[ Info: ", color=6, bold=true)
    println("GTP ready")
end 

function leelaz_showboard(proc::Base.Process)
    readuntil(proc.err, "Passes:")
    paragraphErr = "Passes:" * readuntil(proc.err, "\n") * "\n"
    while true
        line = readline(proc.err)
        if line == ""
            continue
        end
        paragraphErr = paragraphErr * line * "\n"
        if occursin("White time:", line)
            break
        end
    end
    paragraphErr
end

function leelaz_showboardf(paragraph)  # f: _format
    lines = split(paragraph, "\n")
    
    infoUp = lines[2:3]
    infoDown = lines[25:27]
    infoAll = cat(infoUp, infoDown, dims=1)
    info = split_undo(infoAll)

    m = n = 19
    linesPosition = lines[5:23]
    c = Vector{String}()
    for line in linesPosition
        line = split(line, [' ', ')', '('])
        for char in line
            if char == "O"
                push!(c, "rgba(255,255,255,1)")
            elseif char == "X"
                push!(c, "rgba(0,0,0,1)")
            elseif char in [".", "+"]
                push!(c, "rgba(0,0,0,0)")
            else 
                continue
            end
        end
    end
    x = repeat([p for p in 1:n], m)
    y = [p for p in m:-1:1 for q in 1:n]

    (x = x, y = y, c = c, i = info)
end

function gnugo_showboardf(paragraph)  # f: _format
    r = r"captured \d{1,}"
    lines = split(paragraph, '\n')
    
    l = length(lines[2]) + 2
    captured = Vector{String}()

    m = length(lines) - 4
    n = length(split(lines[2]))
    #position = zeros(Int64, m, n)
    i = m
    j = 1
    linesPosition = lines[3:2+m]

    c = Vector{String}()

    for line in linesPosition
        if length(line) > l + 20
            captured = cat(captured, match_diy([r, r"\d{1,}"], [line]), dims=1)
        end
        line = split(line)[2:n+1]
        for char in line
            if char == "O"
                #position[i,j] = 1
                push!(c, "rgba(255,255,255,1)")
                j = j + 1
            elseif char == "X"
                #position[i,j] = -1
                push!(c, "rgba(0,0,0,1)")
                j = j + 1
            elseif char in [".", "+"]
                push!(c, "rgba(0,0,0,0)")
                j = j + 1
            elseif j == n
                break
            else 
                continue
            end
        end
        j = 1
        i = i - 1
    end 
    #println(position)

    x = repeat([p for p in 1:n], m)
    y = [p for p in m:-1:1 for q in 1:n]
    
    blackCaptured = captured[1]
    whiteCaptured = captured[2]

    info = """
    B stones captured: $blackCaptured
    W stones captured: $whiteCaptured
    """

    (x = x, y = y, c = c, i = info)
end

function katago_showboardf(paragraph)
    lines = split(paragraph, "\n")

    infoUp = lines[1][3:end]

    n = length(split(lines[2]))
    m = 3
    c = Vector{String}()
    while lines[m][1] in "1 "
        for char in split(lines[m][4:end], [' ', '1', '2', '3'])
            if char == "O"
                push!(c, "rgba(255,255,255,1)")
            elseif char == "X"
                push!(c, "rgba(0,0,0,1)")
            elseif char == "."
                push!(c, "rgba(0,0,0,0)")
            else 
                continue
            end
        end
        m=m+1
    end
    m = m - 3
    x = repeat([p for p in 1:n], m)
    y = [p for p in m:-1:1 for q in 1:n]

    infoDown = lines[m+3:m+6]
    infoAll = cat(infoUp, infoDown, dims=1)
    info = split_undo(infoAll)

    (x = x, y = y, c = c, i = info)
end

function showboard_get(proc::Base.Process)
    paragraph = reply(proc)
    name = name_get(proc)
    if name == "Leela Zero"
        paragraph = paragraph * leelaz_showboard(proc)
    end
    #println(paragraph)
    paragraph
end 

showboard_format((paragraph, name)) = showboard_format(paragraph, name)
function showboard_format(paragraph, name)
    name = name_get(proc)
    board = NamedTuple()
    if name == "GNU Go"
        board = gnugo_showboardf(paragraph)
    elseif name == "Leela Zero"
        board = leelaz_showboardf(paragraph)
    elseif name == "KataGo"
        board = katago_showboardf(paragraph)
    else
    end
    println(dump(board))
    board 
end

function gtp_analyze(proc::Base.Process)
    println(readline(proc))
    println(readline(proc))
    query(proc, "z")
    reply(proc)
    println()
end

function gtp_exit()
    println("=\n")
    exit()
end

function gtp_ps()

end

function gtp_run()

end

function gtp_kill()

end

function gtp_switch()

end

function gtp_help()

end

#=
function gtp_loop(procs::Vector{Base.Process})
    
    proc = procs[1]
    while true 
        sentence = readline()
        if ! gtp_valid(sentence)
            println("? invalid command\n")
            continue
        end 
        sentenceVector = split(sentence)
        if "switch" in sentenceVector
            include_string("proc = $(sentenceVector[2])")
        end
            
end =#
function gtp_loop(proc::Base.Process)
    while true
        sentence = readline()
        sentenceVector = split(sentence)
        if "exit" in sentenceVector
            gtp_exit()
        elseif "ps" in sentenceVector
        elseif "run" in sentenceVector  # [id] cmd [args]
        elseif "kill" in sentenceVector  # [id] cmd [args]
        elseif "switch" in sentenceVector  # [id] cmd [args]
        elseif "help" in sentenceVector

        elseif gtp_valid(sentence)
            query(proc, sentence)
        else 
            println("? invalid command\n")
            continue
        end 
        
        if "quit" in sentenceVector
            bot_end(proc)
        elseif "showboard" in sentenceVector
            proc |> showboard_get |> println
        elseif "showboardf" in sentenceVector
            proc |> reply
            (proc, "showboard") |> query
            proc |> showboard_get |> showboard_format
        elseif occursin("analyze", sentence)
            gtp_analyze(proc)
        else
            println(reply(proc))
        end
    end
end

function terminal()
    botSet = bot_get()
    bot = botSet.dict[ARGS[1]]
    botProcess = bot_run(dir=bot.dir, cmd=bot.cmd)
    gtp_ready(botProcess)
    gtp_loop(botProcess)
end

terminal()
