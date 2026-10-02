import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Braces extends RecursiveAstVisitor<void> {
  final edits=<(int,String)>[];
  void add(Statement s){if(s is! Block){edits.add((s.offset,'{'));edits.add((s.end,'}'));}}
  @override void visitIfStatement(IfStatement n){add(n.thenStatement);final other=n.elseStatement;if(other!=null&&other is! IfStatement)add(other);super.visitIfStatement(n);}
}
void main(List<String> args){for(final path in args){final file=File(path);var content=file.readAsStringSync();final visitor=Braces();parseString(content:content).unit.accept(visitor);visitor.edits.sort((a,b)=>b.$1.compareTo(a.$1));for(final edit in visitor.edits){content=content.substring(0,edit.$1)+edit.$2+content.substring(edit.$1);}file.writeAsStringSync(content);}}
