/**
This module defines the interfaces that work with statement and expression nodes. Interpreter and Compiler
implements all of these interfaces.
────────────────────────────────────────────────────────────────────────────────
Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
 */
module mildew.visitors;

import std.variant;

import mildew.nodes;

package:

interface IExpressionVisitor
{
	Variant visitLiteralNode(LiteralNode lnode);
    Variant visitFunctionLiteralNode(FunctionLiteralNode flnode);
    Variant visitLambdaNode(LambdaNode lnode);
    Variant visitTemplateStringNode(TemplateStringNode tsnode);
	Variant visitArrayLiteralNode(ArrayLiteralNode alnode);
	Variant visitObjectLiteralNode(ObjectLiteralNode olnode);
	Variant visitClassLiteralNode(ClassLiteralNode clnode);
	Variant visitBinaryOpNode(BinaryOpNode bonode);
	Variant visitUnaryOpNode(UnaryOpNode uonode);
	Variant visitPostfixOpNode(PostfixOpNode ponode);
	Variant visitTerniaryOpNode(TerniaryOpNode tonode);
	Variant visitVarAccessNode(VarAccessNode vanode);
	Variant visitFunctionCallNode(FunctionCallNode fcnode);
	Variant visitArrayIndexNode(ArrayIndexNode ainode);
	Variant visitMemberAccessNode(MemberAccessNode manode);
	Variant visitNewExpressionNode(NewExpressionNode nenode);
    Variant visitSuperNode(SuperNode snode);
}

interface IStatementVisitor 
{
	Variant visitVarDeclarationStatementNode(VarDeclarationStatementNode vdsnode);
	Variant visitBlockStatementNode(BlockStatementNode bsnode);
	Variant visitIfStatementNode(IfStatementNode isnode);
	Variant visitSwitchStatementNode(SwitchStatementNode ssnode);
	Variant visitWhileStatementNode(WhileStatementNode wsnode);
	Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode);
	Variant visitForStatementNode(ForStatementNode fsnode);
	Variant visitForOfStatementNode(ForOfStatementNode fosnode);
	Variant visitBreakStatementNode(BreakStatementNode bsnode);
	Variant visitContinueStatementNode(ContinueStatementNode csnode);
	Variant visitReturnStatementNode(ReturnStatementNode rsnode);
	Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode);
	Variant visitThrowStatementNode(ThrowStatementNode tsnode);
	Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode);
	Variant visitDeleteStatementNode(DeleteStatementNode dsnode);
	Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode);
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode);
}

interface INodeVisitor : IExpressionVisitor, IStatementVisitor {}