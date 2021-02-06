module mildew.visitors;

import std.variant;

import mildew.nodes;

package:

interface IExpressionVisitor
{
	Variant visitLiteralNode(LiteralNode lnode);
    Variant visitFunctionLiteralNode(FunctionLiteralNode flnode);
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
	Variant visitSuperCallStatementNode(SuperCallStatementNode scsnode);
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode);
}

interface INodeVisitor : IExpressionVisitor, IStatementVisitor {}