package org.imm;

import java.io.*;
import java.net.URI;
import java.nio.file.*;
import java.util.*;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

import org.objectweb.asm.*;

public class IMMTransformer {
    public static void main(String[] args) throws IOException {
        // Usage: java -jar <path-to-jar> input_bytecode output_bytecode method_name [jar_path]
        if (args.length < 3) {
            System.err.println("Requires argument: input bytecode file, output bytecode file, method name, and jar path [optional]");
            System.exit(1);
        }

        String inputFile = args[0];
        String outputFile = args[1];
        String methodName = args[2];
        if (methodName.equals("<clinit>")) {
            System.err.println("Cannot de-instrument clinit...");
            System.exit(1);
        }

        if (args.length == 3) {
            modifyProjectCode(inputFile, outputFile, methodName);
        } else {
            String jarPath = args[3];
            modifyLibraryCode(inputFile, outputFile, methodName, jarPath);
        }
    }

    private static void modifyProjectCode(String inputFile, String outputFile, String methodName) throws IOException {
        if (!new File(inputFile).isFile()) {
            System.err.println("Cannot find .class file");
            System.exit(1);
        }

        System.out.println("Processing CUT bytecode " + inputFile);
        processBytecode(Files.newInputStream(Paths.get(inputFile)), methodName, inputFile, outputFile, "");
    }

    private static void modifyLibraryCode(String inputFile, String outputFile, String methodName, String filePath) throws IOException {
        if (!new File(filePath).isFile()) {
            System.err.println("Cannot find .jar/.txt file");
            System.exit(1);
        }

        if (!inputFile.endsWith(".class")) {
            inputFile = inputFile + ".class";
        }

        if (inputFile.startsWith("/")) {
            inputFile = inputFile.substring(1);
        }

        System.out.println("Processing library bytecode " + inputFile);
        if (filePath.endsWith(".jar")) {
            // filePath is a jar file, directly changing the jar
            if (!modifyLibraryJar(inputFile, outputFile, methodName, filePath)) {
                System.err.println("Cannot find .class file in jar " + filePath);
                System.exit(1);
            }
        } else {
            // filePath is a txt file, which contains a list of jar, check jar one by one
            String classpath = Files.readAllLines(Paths.get(filePath)).get(0);
            for (String potentialJarPath : classpath.split(":")) {
                if (!potentialJarPath.endsWith(".jar"))
                    continue;

                if (modifyLibraryJar(inputFile, outputFile, methodName, potentialJarPath)) {
                    return;
                }
            }

            System.err.println("Cannot find .class file in classpath " + classpath);
            System.exit(1);
        }
    }

    private static boolean modifyLibraryJar(String inputFile, String outputFile, String methodName, String jarPath) throws IOException {
        try (JarFile jarFile = new JarFile(jarPath)) {
            Enumeration<JarEntry> entries = jarFile.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String filename = entry.getName();
                if (filename.endsWith(".class")) {
                    if (filename.equals(inputFile)) {
                        System.out.println("Found file " + filename + " in " + jarPath);
                        Patcher.patchJar(jarPath);
                        processBytecode(jarFile.getInputStream(entry), methodName, inputFile, outputFile, jarPath);
                        return true;
                    }
                }
            }
        }

        return false;
    }

    private static void processBytecode(InputStream inputStream, String methodName, String inputFile, String outputFile, String jarPath) throws IOException {
        System.out.println("> Finding all method signatures related to " + methodName);
        ClassReader classReader = new ClassReader(inputStream);
        MethodLocatorClassVisitor locatorVisitor = new MethodLocatorClassVisitor(methodName);
        classReader.accept(locatorVisitor, ClassReader.SKIP_FRAMES);

        int targetMethodLOC = locatorVisitor.targetMethodLOC;
        String targetMethodName = locatorVisitor.targetMethodName;
        Set<String> matchingSignatures = locatorVisitor.matchingSignatures;
        int majorVersion = locatorVisitor.majorVersion;

        if (matchingSignatures.isEmpty()) {
            if (locatorVisitor.allSignatures.size() == 1) {
                matchingSignatures = locatorVisitor.allSignatures;
                System.out.println("Cannot find method with matching line: " + methodName + ", but can find ONE method with desc: " + matchingSignatures);
            } else if (locatorVisitor.allSignatures.isEmpty()) {
                System.err.println("Cannot find method with matching line: " + methodName);
                System.exit(1);
            } else {
                System.err.println("Cannot find method with matching line: " + methodName + ", there are multiple methods");
                System.exit(1);
            }
        }

        System.out.println("Found signatures " + matchingSignatures + " with location " + targetMethodLOC);

        System.out.println("> Cloning method " + methodName);

        boolean isInterface = (classReader.getAccess() & Opcodes.ACC_INTERFACE) != 0;
        String interfaceID = "IMM" + UUID.randomUUID().toString().replace('-', '_');
        ClassWriter classWriter = new ClassWriter(classReader, ClassWriter.COMPUTE_MAXS);
        DuplicateIMMClassVisitor classVisitor = new DuplicateIMMClassVisitor(classWriter, targetMethodName, targetMethodLOC, true, !isInterface ? "" : interfaceID, matchingSignatures);
        classReader.accept(classVisitor, ClassReader.EXPAND_FRAMES);

        System.out.println("> Adding guards to method " + methodName);

        byte[] bytes = classWriter.toByteArray();
        ClassReader classReader2 = new ClassReader(bytes);
        ClassWriter classWriter2 =  majorVersion < 50 ? new ClassWriter(classReader2, 0) : new ClassWriter(classReader2, ClassWriter.COMPUTE_FRAMES);
        DuplicateIMMClassVisitor classVisitor2 = new DuplicateIMMClassVisitor(classWriter2, targetMethodName, targetMethodLOC, false, !isInterface ? "" : interfaceID, matchingSignatures);
        classReader2.accept(classVisitor2, ClassReader.SKIP_FRAMES);
        bytes = classWriter2.toByteArray();

        if (isInterface) {
            System.out.println("> Generate class to store interface variables in method " + methodName);
            // input is an interface, we cannot add flag to the interface, so we add flag to another file

            int classLast = classVisitor.className.lastIndexOf('/');
            ClassWriter classWriter3 = new ClassWriter(0);
            DuplicateIMMInterfaceClassVisitor classVisitor3 = new DuplicateIMMInterfaceClassVisitor(classWriter3, classVisitor.IMMFlagName, targetMethodLOC);
            classVisitor3.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC,
                    classLast < 0 ? interfaceID : (classVisitor.className.substring(0, classLast) + "/" + interfaceID),
                    null, "java/lang/Object", null);
            classVisitor3.visitEnd();

            int inputLast = inputFile.lastIndexOf('/');
            String newInputFile = inputFile.equals("replace") ? inputFile : (inputLast < 0 ? (interfaceID + ".class") : (inputFile.substring(0, inputLast) + "/" + interfaceID + ".class"));

            int outputLast = outputFile.lastIndexOf('/');
            String newOutputFile = outputFile.equals("replace") ? outputFile : (outputLast < 0 ? (interfaceID + ".class") : (outputFile.substring(0, outputLast) + "/" + interfaceID + ".class"));

            writeToFile(classWriter3.toByteArray(), newInputFile, newOutputFile, jarPath);
            System.out.println("input: " + newInputFile + ", output: " + newOutputFile);
        }

        writeToFile(bytes, inputFile, outputFile, jarPath);

        System.out.println("Matching descriptions:");
        for (String sig : matchingSignatures) {
            System.out.println(sig);
        }
    }

    private static void writeToFile(byte[] bytes, String inputFile, String outputFile, String jarPath) throws IOException {
        if (outputFile.equals("replace")) {
            if (!jarPath.isEmpty()) {
                // Replace file inside jar

                File file = new File("tmp.class");
                FileOutputStream fos = new FileOutputStream(file);
                fos.write(bytes);
                fos.close();

                try (FileSystem fs = FileSystems.newFileSystem(URI.create("jar:file:" + jarPath), new HashMap<String, String>())) {
                    Path newFile = Paths.get("tmp.class");
                    Path oldFile = fs.getPath(inputFile);
                    Files.copy(newFile, oldFile, StandardCopyOption.REPLACE_EXISTING);
                }

                file.delete();
                return;
            }

            outputFile = inputFile;
        }

        File file = new File(outputFile);
        FileOutputStream fos = new FileOutputStream(file);
        fos.write(bytes);
        fos.close();
    }
}
