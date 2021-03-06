module gen

import (
	strings
	v.ast
	v.table
	term
)

struct Gen {
	out         strings.Builder
	definitions strings.Builder // typedefs, defines etc (everything that goes to the top of the file)
	table       &table.Table
mut:
	fn_decl     &ast.FnDecl // pointer to the FnDecl we are currently inside otherwise 0
	tmp_count   int
}

pub fn cgen(files []ast.File, table &table.Table) string {
	println('start cgen')
	mut g := Gen{
		out: strings.new_builder(100)
		definitions: strings.new_builder(100)
		table: table
		fn_decl: 0
	}
	for file in files {
		g.stmts(file.stmts)
	}
	return g.definitions.str() + g.out.str()
}

pub fn (g &Gen) save() {}

pub fn (g mut Gen) write(s string) {
	g.out.write(s)
}

pub fn (g mut Gen) writeln(s string) {
	g.out.writeln(s)
}

pub fn (g mut Gen) new_tmp_var() string {
	g.tmp_count++
	return 'tmp$g.tmp_count'
}

pub fn (g mut Gen) reset_tmp_count() {
	g.tmp_count = 0
}

fn (g mut Gen) stmts(stmts []ast.Stmt) {
	for stmt in stmts {
		g.stmt(stmt)
		g.writeln('')
	}
}

fn (g mut Gen) stmt(node ast.Stmt) {
	// println('cgen.stmt()')
	// g.writeln('//// stmt start')
	match node {
		ast.Import {}
		ast.ConstDecl {
			for i, field in it.fields {
				field_type_sym := g.table.get_type_symbol(field.typ)
				g.write('$field_type_sym.name $field.name = ')
				g.expr(it.exprs[i])
				g.writeln(';')
			}
		}
		ast.FnDecl {
			g.reset_tmp_count()
			g.fn_decl = it // &it
			is_main := it.name == 'main'
			if is_main {
				g.write('int ${it.name}(')
			}
			else {
				type_sym := g.table.get_type_symbol(it.typ)
				g.write('$type_sym.name ${it.name}(')
				g.definitions.write('$type_sym.name ${it.name}(')
			}
			for i, arg in it.args {
				arg_type_sym := g.table.get_type_symbol(arg.typ)
				mut arg_type_name := arg_type_sym.name
				if i == it.args.len - 1 && it.is_variadic {
					arg_type_name = 'variadic_$arg_type_sym.name'
				}
				g.write(arg_type_name + ' ' + arg.name)
				g.definitions.write(arg_type_name + ' ' + arg.name)
				if i < it.args.len - 1 {
					g.write(', ')
					g.definitions.write(', ')
				}
			}
			g.writeln(') { ')
			if !is_main {
				g.definitions.writeln(');')
			}
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			if is_main {
				g.writeln('return 0;')
			}
			g.writeln('}')
			g.fn_decl = 0
		}
		ast.Return {
			g.write('return')
			// multiple returns
			if it.exprs.len > 1 {
				type_sym := g.table.get_type_symbol(g.fn_decl.typ)
				g.write(' ($type_sym.name){')
				for i, expr in it.exprs {
					g.write('.arg$i=')
					g.expr(expr)
					if i < it.exprs.len - 1 {
						g.write(',')
					}
				}
				g.write('}')
			}
			// normal return
			else if it.exprs.len == 1 {
				g.write(' ')
				g.expr(it.exprs[0])
			}
			g.writeln(';')
		}
		ast.AssignStmt {
			// ident0 := it.left[0]
			// info0 := ident0.var_info()
			// for i, ident in it.left {
			// info := ident.var_info()
			// if info0.typ.typ.kind == .multi_return {
			// if i == 0 {
			// g.write('$info.typ.typ.name $ident.name = ')
			// g.expr(it.right[0])
			// } else {
			// arg_no := i-1
			// g.write('$info.typ.typ.name $ident.name = $ident0.name->arg[$arg_no]')
			// }
			// }
			// g.writeln(';')
			// }
			println('assign')
		}
		ast.VarDecl {
			type_sym := g.table.get_type_symbol(it.typ)
			g.write('$type_sym.name $it.name = ')
			g.expr(it.expr)
			g.writeln(';')
		}
		ast.ForStmt {
			g.write('while (')
			g.expr(it.cond)
			g.writeln(') {')
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			g.writeln('}')
		}
		ast.ForCStmt {
			g.write('for (')
			g.stmt(it.init)
			// g.write('; ')
			g.expr(it.cond)
			g.write('; ')
			g.stmt(it.inc)
			g.writeln(') {')
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			g.writeln('}')
		}
		ast.StructDecl {
			g.writeln('typedef struct {')
			for field in it.fields {
				field_type_sym := g.table.get_type_symbol(field.typ)
				g.writeln('\t$field_type_sym.name $field.name;')
			}
			g.writeln('} $it.name;')
		}
		ast.ExprStmt {
			g.expr(it.expr)
			match it.expr {
				// no ; after an if expression
				ast.IfExpr {}
				else {
					g.writeln(';')
				}
	}
		}
		else {
			verror('cgen.stmt(): bad node')
		}
	}
}

fn (g mut Gen) expr(node ast.Expr) {
	// println('cgen expr()')
	match node {
		ast.ArrayInit {
			type_sym := g.table.get_type_symbol(it.typ)
			g.writeln('new_array_from_c_array($it.exprs.len, $it.exprs.len, sizeof($type_sym.name), {\t')
			for expr in it.exprs {
				g.expr(expr)
				g.write(', ')
			}
			g.write('\n})')
		}
		ast.AssignExpr {
			g.expr(it.left)
			g.write(' $it.op.str() ')
			g.expr(it.val)
		}
		ast.BoolLiteral {
			g.write(it.val.str())
		}
		ast.IntegerLiteral {
			g.write(it.val.str())
		}
		ast.FloatLiteral {
			g.write(it.val)
		}
		ast.PostfixExpr {
			g.expr(it.expr)
			g.write(it.op.str())
		}
		/*
		ast.UnaryExpr {
			// probably not :D
			if it.op in [.inc, .dec] {
				g.expr(it.left)
				g.write(it.op.str())
			}
			else {
				g.write(it.op.str())
				g.expr(it.left)
			}
		}
		*/

		ast.StringLiteral {
			g.write('tos3("$it.val")')
		}
		ast.PrefixExpr {
			g.write(it.op.str())
			g.expr(it.right)
		}
		ast.InfixExpr {
			g.expr(it.left)
			if it.op == .dot {
				println('!! dot')
			}
			g.write(' $it.op.str() ')
			g.expr(it.right)
			// if typ.name != typ2.name {
			// verror('bad types $typ.name $typ2.name')
			// }
		}
		// `user := User{name: 'Bob'}`
		ast.StructInit {
			type_sym := g.table.get_type_symbol(it.typ)
			g.writeln('($type_sym.name){')
			for i, field in it.fields {
				g.write('\t.$field = ')
				g.expr(it.exprs[i])
				g.writeln(', ')
			}
			g.write('}')
		}
		ast.CallExpr {
			g.write('${it.name}(')
			for i, expr in it.args {
				g.expr(expr)
				if i != it.args.len - 1 {
					g.write(', ')
				}
			}
			g.write(')')
		}
		ast.MethodCallExpr {}
		ast.Ident {
			g.write('$it.name')
		}
		ast.SelectorExpr {
			g.expr(it.expr)
			g.write('.')
			g.write(it.field)
		}
		ast.IndexExpr {
			g.index_expr(it)
		}
		ast.IfExpr {
			// If expression? Assign the value to a temp var.
			// Previously ?: was used, but it's too unreliable.
			type_sym := g.table.get_type_symbol(it.typ)
			mut tmp := ''
			if type_sym.kind != .void {
				tmp = g.new_tmp_var()
				// g.writeln('$ti.name $tmp;')
			}
			g.write('if (')
			g.expr(it.cond)
			g.writeln(') {')
			for i, stmt in it.stmts {
				// Assign ret value
				if i == it.stmts.len - 1 && type_sym.kind != .void {
					// g.writeln('$tmp =')
					println(1)
				}
				g.stmt(stmt)
			}
			g.writeln('}')
			if it.else_stmts.len > 0 {
				g.writeln('else { ')
				for stmt in it.else_stmts {
					g.stmt(stmt)
				}
				g.writeln('}')
			}
		}
		ast.MatchExpr {
			type_sym := g.table.get_type_symbol(it.typ)
			mut tmp := ''
			if type_sym.kind != .void {
				tmp = g.new_tmp_var()
			}
			g.write('$type_sym.name $tmp = ')
			g.expr(it.cond)
			g.writeln(';') // $it.blocks.len')
			for i, block in it.blocks {
				match_expr := it.match_exprs[i]
				g.write('if $tmp == ')
				g.expr(match_expr)
				g.writeln('{')
				g.stmts(block.stmts)
				g.writeln('}')
			}
		}
		else {
			println(term.red('cgen.expr(): bad node'))
		}
	}
}

fn (g mut Gen) index_expr(node ast.IndexExpr) {
	// TODO else doesn't work with sum types
	mut is_range := false
	match node.index {
		ast.RangeExpr {
			is_range = true
			g.write('array_slice(')
			g.expr(node.left)
			g.write(', ')
			// g.expr(it.low)
			g.write('0')
			g.write(', ')
			g.expr(it.high)
			g.write(')')
		}
		else {}
	}
	if !is_range {
		g.expr(node.left)
		g.write('[')
		g.expr(node.index)
		g.write(']')
	}
}

fn verror(s string) {
	println(s)
	exit(1)
}
