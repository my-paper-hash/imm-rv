package org.imm;

import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.Label;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import static org.objectweb.asm.Opcodes.ASM6;

public class MethodLocatorClassVisitor extends ClassVisitor {

    public String targetMethodName;
    public int targetMethodLOC = -1;
    public String targetDesc = "";
    public int majorVersion = 0;

    public Set<String> matchingSignatures = new HashSet<>();
    public Set<String> allSignatures = new HashSet<>();


    protected MethodLocatorClassVisitor(String targetMethodName) {
        super(Opcodes.ASM6);

        String[] methodAndLoc = targetMethodName.split(":");
        this.targetMethodName = methodAndLoc[0];
        if (methodAndLoc.length < 2) {
            this.targetMethodLOC = -1;
        } else {
            String[] desc = methodAndLoc[1].split("#");
            if (desc.length < 2) {
                this.targetMethodLOC = Integer.parseInt(methodAndLoc[1]);
                System.out.println("Searching line number " + this.targetMethodLOC);
            } else {
                this.targetMethodLOC = Integer.parseInt(desc[0]);
                this.targetDesc = desc[1];
                System.out.println("Searching method desc " + this.targetDesc + ", old line number " + this.targetMethodLOC);
            }
        }
    }

    @Override
    public void visit(int version, int access, String name, String signature,
                      String superName, String[] interfaces) {
        super.visit(version, access, name, signature, superName, interfaces);
        this.majorVersion = version & 0xFFFF;
        System.out.println("Bytecode major version: " + majorVersion);
    }

    @Override
    public MethodVisitor visitMethod(int access, String name, String desc,
                                     String signature, String[] exceptions) {
        MethodVisitor methodVisitor = super.visitMethod(access, name, desc, signature, exceptions);
        if ((access & Opcodes.ACC_BRIDGE) != 0) {
            return methodVisitor;
        }

        if (name.equals(this.targetMethodName)) {
            allSignatures.add(desc);

            return new MethodVisitor(ASM6) {
                @Override
                public void visitLineNumber(int line, Label start) {
                    super.visitLineNumber(line, start);
                    if (!targetDesc.isEmpty()) {
                        if (targetDesc.equals(desc)) {
                            System.out.println("Method " + name + " found target desc: " + desc + " with new line number " + line);
                            matchingSignatures.add(desc);
                        }
                    } else if (line == targetMethodLOC) {
                        System.out.println("Method " + name + " found target line number " + line + " with desc: " + desc);
                        matchingSignatures.add(desc);
                    }
                }
            };
        }
        return methodVisitor;
    }
}
