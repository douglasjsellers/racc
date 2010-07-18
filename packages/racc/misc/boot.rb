# $Id: boot.rb,v 1.2 2005/11/20 15:14:55 aamine Exp $

require 'racc/compat'
require 'racc/info'
require 'racc/grammar'
require 'racc/state'
require 'racc/output'
require 'stringio'

module Racc

  class State
    undef sr_conflict
    def sr_conflict(*args)
      raise 'Racc boot script fatal: S/R conflict in build'
    end

    undef rr_conflict
    def rr_conflict(*args)
      raise 'Racc boot script fatal: R/R conflict in build'
    end
  end


  class BootstrapCompiler

    def BootstrapCompiler.main
      c = Racc::BootstrapCompiler.new
      c.build ARGV.delete('-g')
      File.foreach(ARGV[0]) do |line|
        if /STATE_TRANSITION_TABLE/ =~ line
          Racc::CodeGenerator.new(c).output $stdout
        else
          print line
        end
      end
      File.open("#{__FILE__}.output", 'w') {|f|
        Racc::VerboseOutputter.new(c).output f
      }
    end

    # called from lib/racc/pre-setup
    def BootstrapCompiler.generate(infile)
      c = Racc::BootstrapCompiler.new
      c.build false
      File.read(infile).sub(/STATE_TRANSITION_TABLE/) {
        out = StringIO.new
        Racc::CodeGenerator.new(c).output out
        out.string
      }
    end

    def initialize
      @ruletable = nil
      @symboltable = nil
      @statetable = nil
    end

    attr_reader :ruletable
    attr_reader :symboltable
    attr_reader :statetable

    def filename
      '(boot.rb)'
    end

    def debug_parser() @dflag end
    def convert_line() true end
    def omit_action()  true end
    def result_var()   true end

    def debug()   false end
    def d_parse() false end
    def d_rule()  false end
    def d_token() false end
    def d_state() false end
    def d_la()    false end
    def d_prec()  false end

    def _(rulestr, actstr)
      nonterm, symlist = *parse_rule_exp(rulestr)
      lineno = caller(1)[0].split(':')[1].to_i + 1
      symlist.push UserAction.new(format_action(actstr), lineno)
      @ruletable.register_rule nonterm, symlist
    end

    def parse_rule_exp(str)
      tokens = str.strip.scan(/[\:\|]|'.'|\w+/)
      nonterm = (tokens[0] == '|') ? nil : @symboltable.get(tokens.shift.intern)
      tokens.shift   # discard ':' or '|'
      return nonterm,
             tokens.map {|t|
               @symboltable.get(if /\A'/ === t
                                then eval(%Q<"#{t[1..-2]}">)
                                else t.intern
                                end)
             }
    end

    def format_action(str)
      str.sub(/\A */, '').sub(/\s+\z/, '')\
          .map {|line| line.sub(/\A {20}/, '') }.join('')
    end

    def build(debugflag)
      @dflag = debugflag

      @symboltable = SymbolTable.new(self)
      @ruletable   = RuleTable.new(self)
      @statetable  = StateTable.new(self)


_"  xclass      : XCLASS class params XRULE rules opt_end                ",
                   %{
                        @ruletable.end_register_rule
                    }

_"  class       : rubyconst                                              ",
                   %{
                        @class_name = val[0]
                    }
_"              | rubyconst '<' rubyconst                                ",
                   %{
                        @class_name = val[0]
                        @super_class = val[2]
                    }

_"  rubyconst   : XSYMBOL                                                ",
                   %{
                        result = result.id2name
                    }
_"              | rubyconst ':'':' XSYMBOL                               ",
                   %{
                        result << '::' << val[3].id2name
                    }

_"  params      :                                                        ", ''
_"              | params param_seg                                       ", ''

_"  param_seg   : XCONV convdefs XEND                                    ",
                   %{
                        @symboltable.end_register_conv
                    }
_"              | xprec                                                  ", ''
_"              | XSTART symbol                                          ",
                   %{
                        @ruletable.register_start val[1]
                    }
_"              | XTOKEN symbol_list                                     ",
                   %{
                        @symboltable.register_token val[1]
                    }
_"              | XOPTION bare_symlist                                   ",
                   %{
                        val[1].each do |s|
                          @ruletable.register_option s.to_s
                        end
                    }
_"              | XEXPECT DIGIT                                          ",
                   %{
                        @ruletable.expect val[1]
                    }

_"  convdefs    : symbol STRING                                          ",
                   %{
                        @symboltable.register_conv val[0], val[1]
                    }
_"              | convdefs symbol STRING                                 ",
                   %{
                        @symboltable.register_conv val[1], val[2]
                    }

_"  xprec       : XPRECHIGH preclines XPRECLOW                           ",
                   %{
                        @symboltable.end_register_prec true
                    }
_"              | XPRECLOW preclines XPRECHIGH                           ",
                   %{
                        @symboltable.end_register_prec false
                    }

_"  preclines   : precline                                               ", ''
_"              | preclines precline                                     ", ''

_"  precline    : XLEFT symbol_list                                      ",
                   %{
                        @symboltable.register_prec :Left, val[1]
                    }
_"              | XRIGHT symbol_list                                     ",
                   %{
                        @symboltable.register_prec :Right, val[1]
                    }
_"              | XNONASSOC symbol_list                                  ",
                   %{
                        @symboltable.register_prec :Nonassoc, val[1]
                    }

_"  symbol_list : symbol                                                 ",
                   %{
                        result = val
                    }
_"              | symbol_list symbol                                     ",
                   %{
                        result.push val[1]
                    }
_"              | symbol_list '|'                                        ", ''

_"  symbol      : XSYMBOL                                                ",
                   %{
                        result = @symboltable.get(result)
                    }
_"              | STRING                                                 ",
                   %{
                        result = @symboltable.get(eval(%Q<"\#{result}">))
                    }

_"  rules       : rules_core                                             ",
                   %{
                        unless result.empty?
                          @ruletable.register_rule_from_array result
                        end
                    }
_"              |                                                        ", ''

_"  rules_core  : symbol                                                 ",
                   %{
                        result = val
                    }
_"              | rules_core rule_item                                   ",
                   %{
                        result.push val[1]
                    }
_"              | rules_core ';'                                         ",
                   %{
                        unless result.empty?
                          @ruletable.register_rule_from_array result
                        end
                        result.clear
                    }
_"              | rules_core ':'                                         ",
                   %{
                        pre = result.pop
                        unless result.empty?
                          @ruletable.register_rule_from_array result
                        end
                        result = [pre]
                    }

_"  rule_item   : symbol                                                 ", ''
_"              | '|'                                                    ",
                   %{
                        result = OrMark.new(@scanner.lineno)
                    }
_"              | '=' symbol                                             ",
                   %{
                        result = Prec.new(val[1], @scanner.lineno)
                    }
_"              | ACTION                                                 ",
                   %{
                        result = UserAction.new(*result)
                    }

_"  bare_symlist: XSYMBOL                                                ",
                   %{
                        result = [ result.id2name ]
                    }
_"              | bare_symlist XSYMBOL                                   ",
                   %{
                        result.push val[1].id2name
                    }

_"  opt_end     : XEND                                                   ", ''
_"              |                                                        ", ''


      @ruletable.init
      @statetable.init
      @statetable.determine
    end

  end

end   # module Racc

if $0 == __FILE__
  Racc::BootstrapCompiler.main
end
