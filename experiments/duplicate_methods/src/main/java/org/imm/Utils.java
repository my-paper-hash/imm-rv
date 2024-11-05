package org.imm;

import org.objectweb.asm.Type;

public class Utils {
    public static String convertAsmSignatureToJava(String desc) {
        StringBuilder javaSignature = new StringBuilder();
        Type[] argumentTypes = Type.getArgumentTypes(desc);
        String returnType = Type.getReturnType(desc).getClassName();
        String[] temps = returnType.split("\\.");
        javaSignature.append(temps[temps.length - 1]);

        javaSignature.append("(");
        for (int i = 0; i < argumentTypes.length; i++) {
            String temp = argumentTypes[i].getClassName();
            temps = temp.split("\\.");
            javaSignature.append(temps[temps.length - 1]);
            if (i < argumentTypes.length - 1) {
                javaSignature.append(",");
            }
        }
        javaSignature.append(")");
        return javaSignature.toString();
    }
}
