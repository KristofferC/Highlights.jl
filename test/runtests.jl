using Highlights, Compat

if VERSION >= v"0.5.0-dev+7720"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end


#
# Utilities.
#

const __DIR__ = dirname(@__FILE__)

function tokentest(lexer, source, expects...)
    local tokens = Highlights.Compiler.lex(source, lexer).tokens
    @test length(tokens) == length(expects)
    @test join([s for (n, s) in expects]) == source
    for (token, (name, str)) in zip(tokens, expects)
        @test token.value == name
        @test SubString(source, token.first, token.last) == str
    end
end

function print_all(lexer, file)
    local source = readstring(joinpath(__DIR__, "samples", file))
    local buffer = IOBuffer()
    for m in ["html", "latex"]
        mime = MIME("text/$m")
        for theme in subtypes(Themes.AbstractTheme)
            stylesheet(buffer, mime, theme)
            highlight(buffer, mime, source, lexer, theme)
        end
    end
    return buffer
end

#
# Setup.
#

using Highlights.Tokens, Highlights.Themes, Highlights.Lexers

# Error reporting for broken lexers.
abstract BrokenLexer <: Highlights.AbstractLexer
@lexer BrokenLexer Dict(
    :tokens => Dict(:root => [(r"\w+", TEXT, (:b, :a))], :a => [], :b => []),
)

# Lexer inheritance.
abstract ParentLexer <: Highlights.AbstractLexer
abstract ChildLexer <: ParentLexer
@lexer ParentLexer Dict(
    :tokens => Dict(:root => [(r"#.*$"m, COMMENT)])
)
@lexer ChildLexer Dict(
    :tokens => Dict(:root => [:__inherit__, (r"\d+", NUMBER), (r".", TEXT)])
)

abstract NumberLexer <: Highlights.AbstractLexer
@lexer NumberLexer Dict(
    :tokens => Dict(
        :root => [
            (r"0b[0-1]+", NUMBER_BIN),
            (r"0o[0-7]+", NUMBER_OCT),
            (r"0x[0-9a-f]+", NUMBER_HEX),
        ],
        :integers => [
            (r"\d+", NUMBER_INTEGER),
        ],
    ),
)

abstract SelfLexer <: Highlights.AbstractLexer
@lexer SelfLexer Dict(
    :tokens => Dict(
        :root => [
            (r"(#)( )(.+)(;)$"m, (COMMENT, WHITESPACE, :root, PUNCTUATION)),
            (r"(!)( )(.+)(;)$"m, (COMMENT, WHITESPACE, :string, PUNCTUATION)),
            (r"\d+", NUMBER),
            (r"\w+", NAME),
            (r" ", WHITESPACE),
        ],
        :string => [
            (r"'[^']*'", STRING),
            (r"0[box][\da-f]+", NumberLexer),
            (r"\d+", NumberLexer => :integers),
            (r"\s", WHITESPACE),
        ],
    ),
)

#
# Testsets.
#

@testset "Highlights" begin
    @testset "Lexers" begin
        @testset for file in readdir(joinpath(__DIR__, "lexers"))
            include("lexers/$file")
        end
        @testset "Self-referencing" begin
            tokentest(
                SelfLexer,
                "# word;",
                COMMENT => "#",
                WHITESPACE => " ",
                NAME => "word",
                PUNCTUATION => ";",
            )
            tokentest(
                SelfLexer,
                "# 1 word;",
                COMMENT => "#",
                WHITESPACE => " ",
                NUMBER => "1",
                WHITESPACE => " ",
                NAME => "word",
                PUNCTUATION => ";",
            )
            tokentest(
                SelfLexer,
                "! '...';",
                COMMENT => "!",
                WHITESPACE => " ",
                STRING => "'...'",
                PUNCTUATION => ";",
            )
            tokentest(
                SelfLexer,
                "! 0b1010;",
                COMMENT => "!",
                WHITESPACE => " ",
                NUMBER_BIN => "0b1010",
                PUNCTUATION => ";",
            )
            tokentest(
                SelfLexer,
                "! 0b1010 0xacd1;",
                COMMENT => "!",
                WHITESPACE => " ",
                NUMBER_BIN => "0b1010",
                WHITESPACE => " ",
                NUMBER_HEX => "0xacd1",
                PUNCTUATION => ";",
            )
            tokentest(
                SelfLexer,
                "! 1234 0b01;",
                COMMENT => "!",
                WHITESPACE => " ",
                NUMBER_INTEGER => "1234",
                WHITESPACE => " ",
                NUMBER_BIN => "0b01",
                PUNCTUATION => ";",
            )
        end
        @testset "Inheritance" begin
            tokentest(
                ParentLexer,
                "# ...",
                COMMENT => "# ...",
            )
            tokentest(
                ParentLexer,
                "1 # ...",
                ERROR => "1",
                ERROR => " ",
                COMMENT => "# ...",
            )
            tokentest(
                ChildLexer,
                "1 # ...",
                NUMBER => "1",
                TEXT => " ",
                COMMENT => "# ...",
            )
        end
        @testset "Utilities" begin
            let w = Lexers.words(["if", "else"]; prefix = "\\b", suffix = "\\b")
                @test ismatch(w, "if")
                @test !ismatch(w, "for")
                @test !ismatch(w, "ifelse")
            end
            let c = Highlights.Compiler.Context("@lexer CustomLexer dict(")
                @test Lexers.julia_is_macro_identifier(c) == 1:6
                @test Lexers.julia_is_iterp_identifier(c) == 0:0
            end
            let c = Highlights.Compiler.Context("raw\"\"\"...\"\"\"")
                @test Lexers.julia_is_triple_string_macro(c) == 1:6
            end
        end
        @testset "Errors" begin
            tokentest(BrokenLexer, " ", ERROR => " ")
        end
    end
    @testset "Themes" begin
        let s = Themes.Style("fg: 111")
            @test s.fg == "111111"
            @test s.bg == Themes.NULL_STRING
            @test !s.bold
            @test !s.italic
            @test !s.underline
        end
        let s = Themes.Style("bg: f8c; italic; bold")
            @test s.fg == Themes.NULL_STRING
            @test s.bg == "ff88cc"
            @test s.bold
            @test s.italic
            @test !s.underline
        end
        let t = Themes.maketheme(Themes.DefaultTheme),
            m = Themes.metadata(Themes.DefaultTheme)
            @test t.base == m[:style]
            @test t.styles[1] == m[:tokens][TEXT]
        end
    end
    @testset "Format" begin
        local render = function(mime, style)
            local buffer = IOBuffer()
            Highlights.Format.render(buffer, mime, style)
            return takebuf_string(buffer)
        end
        @testset "CSS" begin
            let mime = MIME("text/css")
                @test render(mime, Themes.Style("fg: 111"))   == "color: #111111; "
                @test render(mime, Themes.Style("bg: 111"))   == "background-color: #111111; "
                @test render(mime, Themes.Style("bold"))      == "font-weight: bold; "
                @test render(mime, Themes.Style("italic"))    == "font-style: italic; "
                @test render(mime, Themes.Style("underline")) == "text-decoration: underline; "
            end
        end
        @testset "LaTeX" begin
            let mime = MIME("text/latex")
                @test render(mime, Themes.Style("fg: 111"))   == "[1]{\\textcolor[HTML]{111111}{#1}}"
                @test render(mime, Themes.Style("bg: 111"))   == "[1]{\\colorbox[HTML]{111111}{#1}}"
                @test render(mime, Themes.Style("bold"))      == "[1]{\\textbf{#1}}"
                @test render(mime, Themes.Style("italic"))    == "[1]{\\textit{#1}}"
                @test render(mime, Themes.Style("underline")) == "[1]{\\underline{#1}}"
            end
        end
    end
    @testset "Compiler" begin
        let buf = IOBuffer()
            Highlights.Compiler.debug(buf, "x", Highlights.Lexers.JuliaLexer)
            @test takebuf_string(buf) == "<NAME> := \"x\"\n"
            # Should print nothing to STDOUT.
            Highlights.Compiler.debug("", Highlights.Lexers.JuliaLexer)
        end
    end
    @testset "Tokens" begin
        @test Highlights.Tokens.TokenValue(:TEXT).value == 1
        @test Highlights.Tokens.parent(:TEXT) == :TEXT
        @test Highlights.Tokens.parent(:COMMENT) == :TEXT
        @test Highlights.Tokens.parent(:COMMENT_SINGLE) == :COMMENT
    end
    @testset "Miscellaneous" begin
        @test Highlights.lexer("julia") == Lexers.JuliaLexer
        @test Highlights.lexer("jl") == Lexers.JuliaLexer
        @test_throws ArgumentError Highlights.lexer("???")
    end
end
