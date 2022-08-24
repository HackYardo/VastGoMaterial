function botget()
    GNUGO = (dir="", cmd="gnugo --mode gtp")
    LEELAZ = (dir="../lzweights/", cmd="leelaz --cpu-only -g -v 8 -w w6.gz")
    KATAGO = (dir="../KataGo/", cmd="./katago gtp -model kgmodels/m6.txt.gz")
    botVector = [GNUGO, LEELAZ, KATAGO]
    
    @label Choose
    println("Choose one or type a new one:\nid dir cmd")
    j = 1
    for i in botVector
        println(j,' ',i.dir,' ',i.cmd)
        j = j + 1 
    end
    println("new\n")
    choose = readline()
    bot = (dir="", cmd="")
    if occursin(choose, "123")
        bot = botVector[parse(Int, choose)]
    elseif choose == "new"
        println("Where is the GTP engine?")
        dir = readline()
        println("What's the command to run it?")
        cmd = readline()
        bot = (dir=dir, cmd=cmd)
    else 
        println("Please try again...")
        @goto Choose 
    end 
    
    return bot
end 

#=
Why Base.PipeEndpoint() && run() or why not open()?
Because stderr is hard to talk with, source:
https://discourse.julialang.org/t/avoiding-readavailable-when-communicating-with-long-lived-external-program/61611/25
=#
function botrun(; dir="", cmd="")
    inp = Base.PipeEndpoint()
    out = Base.PipeEndpoint()
    err = Base.PipeEndpoint()
    
    cmdVector = split(cmd) # otherwise there will be ' in command
    command = Cmd(`$cmdVector`, dir=dir)
    cmdString = "$command"
    println("The julia-style command:\n$cmdString")
    println("IF NO \"GTP ready\", TRY The command IN TERMINAL FIRST, \
        THEN CHECK data/bot.csv\n")
    process = run(command,inp,out,err;wait=false)
    #println("$process")
    return process
end


function name(proc)
    query(proc, "name")
    println("name")  # print to user
    reply(proc)
end

function gtp_startup_info(proc, cmd)
    if occursin("leelaz", cmd)
        println(readuntil(proc.err, "B.", keep=true))
    end
end 

function gtp_ready(cmd)
    if !occursin("katago", cmd)
        println("GTP ready")
    end
end 

function botend(p::Base.Process)
    close(p)
end

function query(proc, sentence::String)
    println(proc, sentence)
end

function reply(proc)
    #=
    paragraph=""
    while true
        sentence=readline(proc)
        if sentence==""
            break
        else 
            paragraph="$paragraph$sentence\n"
        end
    end
    =#
    paragraph = readuntil(proc, r"^$", keep=true)
    println(paragraph)
    return paragraph::String
end

function play()
    bot = botget()
    botProcess = botrun(dir=bot.dir, cmd=bot.cmd)
    gtp_startup_info(botProcess, bot.cmd)
    gtp_ready(bot.cmd)
    while true
        sentence = readline()
        query(botProcess, sentence)
        reply(botProcess)
        if occursin("quit", sentence)
            botend(botProcess)
            break
        else
            continue
        end
    end
end

play()
