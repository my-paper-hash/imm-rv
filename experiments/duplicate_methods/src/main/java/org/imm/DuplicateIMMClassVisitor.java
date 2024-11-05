package org.imm;

import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.util.HashSet;
import java.util.Set;

import static org.objectweb.asm.Opcodes.ASM6;

public class DuplicateIMMClassVisitor extends ClassVisitor {

    public String className = "";
    private String targetMethodName;
    public int targetMethodLOC;
    private String targetDescriptor = "";
    public String IMMFlagName = "";
    private String IMMMethodName;
    public boolean firstVisit;
    private boolean foundClinit = false;
    private String IMMFlagClass; // empty if it is not an interface, else it is a random string to store flags
    public Set<String> matchingSignatures;

    public DuplicateIMMClassVisitor(ClassVisitor classVisitor, String targetMethodName, int targetMethodLOC, boolean firstVisit, String IMMFlagClass, Set<String> matchingSignatures) {
        super(ASM6, classVisitor);
        this.targetMethodName = targetMethodName;
        this.targetMethodLOC = targetMethodLOC;

        if (this.targetMethodName.equals("<init>")) {
            IMMMethodName = "IMM_init";
        } else {
            IMMMethodName = "IMM_" + this.targetMethodName;
        }
        this.firstVisit = firstVisit;
        this.IMMFlagClass = IMMFlagClass;

        this.matchingSignatures = matchingSignatures;
    }

    @Override
    public void visit(int version, int access, String name, String signature,
                      String superName, String[] interfaces) {
        super.visit(version, access, name, signature, superName, interfaces);
        className = name;
        IMMMethodName = IMMMethodName + "_" + name.replace('$', '_').replace('/', '_');
        IMMFlagName = IMMMethodName + "_visited";
    }

    @Override
    public MethodVisitor visitMethod(int access, String name, String desc,
                                     String signature, String[] exceptions) {
        MethodVisitor methodVisitor = super.visitMethod(access, name, desc, signature, exceptions);
        if ((access & Opcodes.ACC_BRIDGE) != 0) {
            return methodVisitor;
        }

        if (name.equals(targetMethodName)) {
            if (!this.matchingSignatures.contains(desc)) {
                System.out.println("Skip " + desc + " is not in matching signature");
                return methodVisitor;
            } else {
                System.out.println("Process method " + desc + " " + (firstVisit ? "first" : "second") + " visit");
            }

            if (firstVisit) {
                MethodVisitor newMethodVisitor = super.visitMethod(access, IMMMethodName + "_" + this.targetMethodLOC, desc, signature, exceptions);
                return new DuplicateIMMMethodVisitor(ASM6, methodVisitor, className, name, this.targetMethodLOC, desc, access, newMethodVisitor, true, IMMFlagClass);
            } else {
                return new DuplicateIMMMethodVisitor(ASM6, methodVisitor, className, name, this.targetMethodLOC, desc, access, null, false, IMMFlagClass);
            }
        }

        if (!firstVisit && IMMFlagClass.isEmpty()) {
            // Source: https://stackoverflow.com/a/14757540
            if (name.equals("<clinit>")) {
                foundClinit = true;
                return new MethodVisitor(ASM6, methodVisitor) {
                    @Override
                    public void visitCode() {
                        System.out.println("Adding flag during visit");
                        cv.visitField(Opcodes.ACC_STATIC, IMMFlagName + "_" + targetMethodLOC, "Z", null, null).visitEnd();
                        methodVisitor.visitInsn(Opcodes.ICONST_0);
                        methodVisitor.visitFieldInsn(Opcodes.PUTSTATIC, className, IMMFlagName + "_" + targetMethodLOC, "Z");
                        methodVisitor.visitCode();

                        super.visitCode();
                    }
                };
            }
        }

        return methodVisitor;
    }

    @Override
    public void visitEnd() {
        // Source: https://stackoverflow.com/a/14757540
        if (!firstVisit && !foundClinit && IMMFlagClass.isEmpty()) {
            System.out.println("Adding flag after visit");
            cv.visitField(Opcodes.ACC_STATIC, IMMFlagName + "_" + this.targetMethodLOC, "Z", null, null).visitEnd();

            MethodVisitor mv = cv.visitMethod(Opcodes.ACC_STATIC, "<clinit>", "()V", null, null);
            if (mv != null) {
                mv.visitCode();

                mv.visitInsn(Opcodes.ICONST_0);
                mv.visitFieldInsn(Opcodes.PUTSTATIC, className, IMMFlagName + "_" + this.targetMethodLOC, "Z");

                mv.visitInsn(Opcodes.RETURN);
                mv.visitMaxs(1, 0); // Specifies the maximum stack size and number of local variables
                mv.visitEnd();
            }

            super.visitEnd();
        }
    }
}