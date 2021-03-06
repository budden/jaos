MODULE Loader; (** AUTHOR "fof"; PURPOSE "Object File Loader"; *)

(* cf. Linker *)

IMPORT SYSTEM, KernelLog, Modules, Streams, Files, D := KernelLog, GenericLinker, ObjectFile, Diagnostics, Strings, StringPool, Trace, Machine;

CONST
	Ok = 0;
	LinkerError=3400;
	FileNotFound = 3401;
	CommandTrapped* = 3904; (* cf module Commands *)

	SupportOldObjectFileFormat = FALSE;
	TraceLoading = FALSE;
TYPE

	HashEntryIntInt = RECORD
		key,value: SIZE;
	END;
	HashIntArray = POINTER TO ARRAY OF HashEntryIntInt;

	HashEntryIntAny = RECORD
		key: SIZE; value: ANY;
	END;

	HashIntAnyArray = POINTER TO ARRAY OF HashEntryIntAny;

	HashTableInt = OBJECT
	VAR
		table: HashIntArray;
		size: LONGINT;
		used-: LONGINT;
		maxLoadFactor: REAL;

		(* Interface *)

		PROCEDURE & Init* (initialSize: LONGINT);
		BEGIN
			ASSERT(initialSize > 2);
			NEW(table, initialSize);
			size := initialSize;
			used := 0;
			maxLoadFactor := 0.75;
		END Init;

		PROCEDURE Put*(key: SIZE; value: SIZE);
		VAR hash: SIZE;
		BEGIN
			ASSERT(key # 0);
			ASSERT(used < size);
			hash := HashValue(key);
			IF table[hash].key = 0 THEN
				INC(used, 1);
			END;
			table[hash].key := key;
			table[hash].value := value;
			IF (used / size) > maxLoadFactor THEN Grow END;
		END Put;

		PROCEDURE Get*(key: SIZE):SIZE;
		BEGIN
			RETURN table[HashValue(key)].value;
		END Get;

		PROCEDURE Has*(key: SIZE):BOOLEAN;
		BEGIN
			RETURN table[HashValue(key)].key = key;
		END Has;

		PROCEDURE Length*():LONGINT;
		BEGIN RETURN used; END Length;

		PROCEDURE Clear*;
		VAR i: LONGINT;
		BEGIN FOR i := 0 TO size - 1 DO table[i].key := 0; END; END Clear;

		(* Internals *)

		PROCEDURE HashValue(key: SIZE):SIZE;
		VAR value, h1, h2, i: SIZE;
		BEGIN
			i := 0;
			value := key;
			h1 := key MOD size;
			h2 := 1; (* Linear probing *)
			REPEAT
				value := (h1 + i*h2) MOD size;
				INC(i);
			UNTIL((table[value].key = 0) OR (table[value].key = key) OR (i > size));
			ASSERT((table[value].key = 0) OR (table[value].key = key));
			RETURN value;
		END HashValue;

		PROCEDURE Grow;
		VAR oldTable: HashIntArray; oldSize, i, key: SIZE;
		BEGIN
			oldSize := size;
			oldTable := table;
			Init(size*2);
			FOR i := 0 TO oldSize-1 DO
				key := oldTable[i].key;
				IF key # 0 THEN
					Put(key, oldTable[i].value);
				END;
			END;
		END Grow;

	END HashTableInt;

	HashTableIntAny* = OBJECT
	VAR
		table: HashIntAnyArray;
		size: LONGINT;
		used-: LONGINT;
		maxLoadFactor: REAL;

		(* Interface *)

		PROCEDURE & Init* (initialSize: LONGINT);
		BEGIN
			ASSERT(initialSize > 2);
			NEW(table, initialSize);
			size := initialSize;
			used := 0;
			maxLoadFactor := 0.75;
		END Init;

		PROCEDURE Put*(key: SIZE; value: ANY);
		VAR hash: SIZE;
		BEGIN
			ASSERT(key # 0);
			ASSERT(used < size);
			hash := HashValue(key);
			IF table[hash].key = 0 THEN
				INC(used, 1);
			END;
			table[hash].key := key;
			table[hash].value := value;
			IF (used / size) > maxLoadFactor THEN Grow END;
		END Put;

		PROCEDURE Get*(key: SIZE):ANY;
		BEGIN
			RETURN table[HashValue(key)].value;
		END Get;

		PROCEDURE Has*(key: SIZE):BOOLEAN;
		BEGIN
			RETURN table[HashValue(key)].key = key;
		END Has;

		PROCEDURE Length*():LONGINT;
		BEGIN RETURN used; END Length;

		PROCEDURE Clear*;
		VAR i: LONGINT;
		BEGIN FOR i := 0 TO size - 1 DO table[i].key := 0; END; END Clear;

		(* Interface for integer values *)

		(* Internals *)

		PROCEDURE HashValue(key: SIZE):SIZE;
		VAR value, h1, h2, i:SIZE;
		BEGIN
			i := 0;
			value := key;
			h1 := key MOD size;
			h2 := 1; (* Linear probing *)
			REPEAT
				value := (h1 + i*h2) MOD size;
				INC(i);
			UNTIL((table[value].key = 0) OR (table[value].key = key) OR (i > size));
			ASSERT((table[value].key = 0) OR (table[value].key = key));
			RETURN value;
		END HashValue;

		PROCEDURE Grow;
		VAR oldTable: HashIntAnyArray; oldSize, i, key: SIZE;
		BEGIN
			oldSize := size;
			oldTable := table;
			Init(size*2);
			FOR i := 0 TO oldSize-1 DO
				key := oldTable[i].key;
				IF key # 0 THEN
					Put(key, oldTable[i].value);
				END;
			END;
		END Grow;

	END HashTableIntAny;

	Data=RECORD size, alignment: SIZE; bytes: Modules.Bytes; address: ADDRESS; END;

	Arrangement* = OBJECT (GenericLinker.Arrangement);
	VAR
		code, data: Data;
		(*moduleAdr: LONGINT;*)
		hasBody: BOOLEAN;
		bodyAddress : ADDRESS;

		PROCEDURE & InitArrangement;
		BEGIN InitData(code); InitData(data); hasBody := FALSE;
		END InitArrangement;

		PROCEDURE Preallocate*(CONST section: ObjectFile.Section);
		BEGIN
			ASSERT(section.unit = 8);
			ASSERT(section.bits.GetSize() MOD 8 = 0);
			ASSERT(section.type # ObjectFile.InitCode);
			IF section.type IN {ObjectFile.Code, ObjectFile.BodyCode} THEN
				DoPreallocate(section, code);
			ELSE ASSERT (section.type IN {ObjectFile.Const, ObjectFile.Data});
				DoPreallocate(section, data);
			END;
		END Preallocate;

		PROCEDURE Allocate* (CONST section: ObjectFile.Section): GenericLinker.Address;
		VAR adr: GenericLinker.Address;
		BEGIN
			IF section.type IN {ObjectFile.Code, ObjectFile.BodyCode} THEN
				adr := DoAllocate(section, code);
			ELSE ASSERT(section.type IN {ObjectFile.Const, ObjectFile.Data});
				adr := DoAllocate(section, data);
			END;

			IF section.type = ObjectFile.BodyCode THEN
				hasBody := TRUE; bodyAddress := adr;
			END;

			(*
			IF (section.identifier.name[0] >= 0) & (section.identifier.name[1] >= 0)  THEN
				IF (section.identifier.name[1] = InternalModuleName) OR (section.identifier.name[2] = InternalModuleName) THEN
					moduleAdr := adr
				END;
			END;
			*)

			RETURN adr;
		END Allocate;

		PROCEDURE Patch* (pos, value: GenericLinker.Address; offset, bits, unit: ObjectFile.Bits);
		VAR char: CHAR;
		BEGIN
			ASSERT(bits MOD 8 = 0);
			ASSERT(unit = 8);

			WHILE bits > 0 DO
				char := CHR(value);
				SYSTEM.PUT(pos, char);
				value := value DIV 256;
				DEC(bits,8); INC(pos,1);
			END;

		END Patch;

	END Arrangement;

	ModuleList=OBJECT
	VAR
		hash: HashTableIntAny;

		PROCEDURE &Init;
		BEGIN
			NEW(hash,128);
		END Init;

		PROCEDURE ThisModule(module: Modules.Module): HashTableInt;
		VAR modList: HashTableInt;
			any: ANY;

			PROCEDURE TraverseScopes(CONST scope: Modules.ExportDesc; level: LONGINT);
			VAR adr: ADDRESS; i: LONGINT;
			BEGIN
				IF (level > 2) THEN RETURN END;
				IF (scope.fp # 0) THEN
					adr := scope.adr;
					IF SupportOldObjectFileFormat THEN
						IF module.staticTypeDescs # testTypeDescs THEN (* old object file format *)
							IF (adr = 0) & (scope.exports > 0)  THEN (* type in old object file format *)
								adr := scope.dsc[0].adr;
								SYSTEM.GET(module.sb + adr, adr);
							ELSIF adr # 0 THEN
								INC(adr,ADDRESSOF(module.code[0]));
							END;
						END;
					END;
					modList.Put(SIZE(scope.fp), adr)
				END;
				FOR i := 0 TO scope.exports-1 DO
					IF scope.dsc # NIL THEN TraverseScopes(scope.dsc[i],level+1) END;
				END;
				adr := 0;
			END TraverseScopes;

		BEGIN{EXCLUSIVE}
			IF hash.Has(SYSTEM.VAL(SIZE, module)) THEN
				any := hash.Get(SYSTEM.VAL(SIZE,module));
				modList := any(HashTableInt);
			ELSE
				NEW(modList,256);  TraverseScopes(module.export,0);
				hash.Put(SYSTEM.VAL(SIZE,module), modList);
				RETURN modList
			END;
			RETURN modList;
		END ThisModule;

	END ModuleList;

	Linker = OBJECT (GenericLinker.Linker)
	VAR
		moduleName: ObjectFile.SegmentedName;
		importBlock: GenericLinker.Block;
		hash: HashTableIntAny;
		moduleBlock: GenericLinker.Block;

		PROCEDURE &InitLinkerX* (diagnostics: Diagnostics.Diagnostics; log: Streams.Writer; code, data: GenericLinker.Arrangement; CONST name: ARRAY OF CHAR);
		BEGIN
			ObjectFile.StringToSegmentedName(name, moduleName);
			InitLinker(diagnostics, log, GenericLinker.UseAllButInitCode (* strip init code *), code, data);
			NEW(importBlock);
			NEW(hash,256); (* hash for blocks *)
		END InitLinkerX;

		(* oerwritten functionality of generic linker *)
		PROCEDURE FindBlock*(CONST identifier: ObjectFile.Identifier): GenericLinker.Block;
		VAR block: GenericLinker.Block; any: ANY;
		BEGIN
			block := NIL;
			IF IsPrefix(moduleName, identifier.name) THEN (* local block *)
				IF identifier.fingerprint = 0 THEN (* not identifiable via fingerprint *)
					block := FindBlock^(identifier);
				ELSE
					any := hash.Get(SYSTEM.VAL(SIZE, identifier.fingerprint));
					IF any # NIL THEN block := any(GenericLinker.Block)  (* local block *) END;
					IF (block # NIL) & (block.identifier.name # identifier.name) THEN (* local block, false or duplicate fingerprint *)
						block := FindBlock^(identifier)
					END;
				END;
			END;
			RETURN block;
		END FindBlock;

		PROCEDURE ExportBlock*(block: GenericLinker.Block);
		BEGIN
			IF block.identifier.fingerprint # 0 THEN
				hash.Put(SYSTEM.VAL(SIZE, block.identifier.fingerprint), block)
			END;
			IF (block.identifier.name[0] >= 0) & (block.identifier.name[1] >= 0)  THEN
				IF (block.identifier.name[1] = InternalModuleName) & (block.identifier.name[2]<0) OR (block.identifier.name[2] = InternalModuleName) & (block.identifier.name[3] < 0) THEN
					moduleBlock := block;
				END;
			END;
		END ExportBlock;

		PROCEDURE ImportBlock*(CONST fixup: ObjectFile.Fixup): GenericLinker.Block;
		VAR name: Modules.Name; res: WORD;
			msg: ARRAY 128 OF CHAR; module: Modules.Module; adr: ADDRESS; m: HashTableInt;
			s: ObjectFile.SectionName; isModule: BOOLEAN; identifier: ObjectFile.Identifier;
			fp: HUGEINT;

			PROCEDURE CheckName(n: StringPool.Index;  name {UNTRACED}: Modules.DynamicName): LONGINT;
			VAR s: ObjectFile.SectionName; i: LONGINT;
			BEGIN
				IF name = NIL THEN RETURN -1 END;
				StringPool.GetString(n, s);
				i := 0;
				WHILE (s[i] # 0X) & (name[i] # 0X) & (s[i] = name[i]) DO
					INC(i);
				END;
				RETURN ORD(s[i]) - ORD(name[i]);
			END CheckName;

			PROCEDURE Error(n: StringPool.Index);
			VAR name: ARRAY 256 OF CHAR;
			BEGIN
				StringPool.GetString(n, name);
				TRACE("Fingerprint does not match",name);
			END Error;


			(* stupid implementation: just search for fp in all exports *)
			PROCEDURE CheckScope(CONST scope: Modules.ExportDesc; level: LONGINT): ADDRESS;
			VAR adr,lo,hi,m,res: SIZE;
			BEGIN
				adr := 0;
				(* export names are sorted, binary search: *)
				lo := 0; hi := scope.exports-1;
				WHILE (lo <= hi) DO
				 	m := (lo + hi) DIV 2;
					res := CheckName(identifier.name[level], scope.dsc[m].name);
					IF res = 0 THEN
						IF (level = LEN(identifier.name)-1) OR (identifier.name[level+1] <= 0) THEN
							(*IF (scope.dsc[m].fp # identifier.fingerprint) & (scope.dsc[m].fp # 0) & (identifier.fingerprint # 0) THEN
								Error(identifier.name[level]);
							END;
							*)
							fp := scope.dsc[m].fp;
							RETURN scope.dsc[m].adr
						ELSE
							RETURN CheckScope(scope.dsc[m], level+1);
						END;
					ELSIF res > 0 THEN lo := m+1;
					ELSE hi := m-1;
					END;
				END;
				RETURN 0;
			END CheckScope;


		BEGIN
			identifier := fixup.identifier;

			IF IsPrefix(moduleName, identifier.name) THEN
				D.String("circular import while trying to fetch ");
				s := identifier.name; D.String(s);
				D.Ln;
				RETURN NIL
			END;

			StringPool.GetString(identifier.name[0], name);
			isModule := identifier.name[1] = InternalModuleName;

			(*
				IF ~isModule & (identifier.fingerprint = 0) THEN
				D.String("Invalid attempt to import symbol without fingerprint ");
				s := identifier.name; D.String(s);
				D.Ln;
				RETURN NIL
			END;
			*)

			module := Modules.ThisModule(name,res,msg);
			IF module = NIL THEN
				D.String("could not get module while importing "); D.String(name); D.Ln;
				RETURN NIL
			END;
			IF isModule THEN
				adr := SYSTEM.VAL(ADDRESS, module) - fixup.patch[0].displacement;
			ELSE
				m := moduleList.ThisModule(module);
				ASSERT(module # NIL);
				(* first try via hash-table *)
				(* disabled -- might be able to remove hash table completely, needs some testing
				IF identifier.fingerprint # 0 THEN
					adr := m.Get(identifier.fingerprint);
				END;
				*)
				(* if it does not work, then try export table directly *)
				IF adr = 0 THEN
					adr := CheckScope(module.export,1(*level*) );
				END;
			END;

			IF adr = 0 THEN
				(*D.String("Loader Fatal error: did not find block "); s := identifier.name; D.String(s); D.Ln;*)
				RETURN NIL;
			ELSE (* found *)
				importBlock.identifier.fingerprint := fp; importBlock.address := adr
			END;
			RETURN importBlock
		END ImportBlock;

	END Linker;

VAR
	moduleList: ModuleList;
	testTypeDescs: Modules.Bytes;
	InternalModuleName: StringPool.Index;

	PROCEDURE InitData(VAR data: Data);
	BEGIN
		data.address := 0; data.size := 0; data.alignment := 0; data.bytes := NIL;
	END InitData;

	PROCEDURE IsPrefix(CONST prefix, of: ObjectFile.SegmentedName): BOOLEAN;
	VAR prefixS, ofS: ObjectFile.SectionName; i: LONGINT;
	BEGIN
		i := 0;
		WHILE (i< LEN(prefix)) & (prefix[i] = of[i]) DO INC(i) END;

		IF i = LEN(prefix) THEN RETURN TRUE (* identical *)
		ELSE (* prefix[i] # of[i] *)
			IF prefix[i] < 0 THEN RETURN TRUE (* name longer than prefix *)
			ELSIF of[i] < 0 THEN RETURN FALSE (* prefix longer than name *)
			ELSIF (i<LEN(prefix)-1) THEN RETURN FALSE (* prefix and name differ but not at the tail *)
			ELSE
				(* check tail *)
				StringPool.GetString(prefix[i], prefixS);
				StringPool.GetString(of[i], ofS);
				RETURN Strings.StartsWith(prefixS, 0, ofS)
			END
		END;
	END IsPrefix;

	PROCEDURE DoPreallocate(CONST section: ObjectFile.Section; VAR data: Data);
	BEGIN
		ASSERT(section.bits.GetSize() MOD 8 = 0);
		IF section.alignment > 0 THEN
			INC(data.size, (-data.size) MOD section.alignment);
			IF section.alignment > data.alignment THEN
				data.alignment := section.alignment;
			END;
		END;
		INC(data.size, section.bits.GetSize() DIV 8);
	END DoPreallocate;

	PROCEDURE DoAllocate(CONST section: ObjectFile.Section; VAR data: Data): ADDRESS;
	VAR address: ADDRESS; size: SIZE;
	BEGIN
		IF (data.bytes = NIL) OR (LEN(data.bytes) # data.size + data.alignment) THEN
			NEW(data.bytes, data.size + data.alignment);
			data.address := ADDRESSOF(data.bytes[0]);
			IF data.alignment > 0 THEN
				INC(data.address, (-data.address) MOD data.alignment);
			END;
		END;

		IF section.alignment > 0 THEN
			INC(data.address, (-data.address) MOD section.alignment);
		END;

		address := data.address;
		size := section.bits.GetSize();
		section.bits.CopyTo(address, size);
		INC(data.address, size DIV 8);
		RETURN address
	END DoAllocate;

	PROCEDURE LoadObj*(CONST name, fileName: ARRAY OF CHAR;  VAR res: WORD; VAR msg: ARRAY OF CHAR): Modules.Module;
	TYPE Body=PROCEDURE;
	VAR
		file: Files.File; reader: Files.Reader; linker: Linker;
		arrangement: Arrangement; diagnostics: Diagnostics.StreamDiagnostics; stringWriter: Streams.StringWriter;
		module: Modules.Module; heapBlockAdr,moduleAdr: ADDRESS;
		Log: Streams.Writer;
	BEGIN
		file := Files.Old(fileName);

		IF file # NIL THEN
			IF TraceLoading THEN Trace.String("loading"); Trace.String(fileName); Trace.Ln END;
			res := Ok; msg[0] := 0X;
			Files.OpenReader(reader, file, 0);
			NEW(arrangement); NEW(stringWriter,256);
			Streams.OpenWriter( Log, KernelLog.Send );
			NEW(diagnostics,Log);
			NEW(linker, diagnostics, NIL, arrangement, arrangement,name);
			IF TraceLoading THEN Trace.String("before linking"); Trace.Ln END;
			GenericLinker.Process (reader, linker);
			IF ~linker.error THEN linker.Resolve END;
			IF ~linker.error THEN linker.Link END;
			(*D.Update;*)
			IF ~linker.error THEN
				IF TraceLoading THEN Trace.String("linking done"); Trace.Ln END;

				moduleAdr := linker.moduleBlock.address;
				#IF ~COOP THEN
					SYSTEM.GET(moduleAdr+2*SIZEOF(ADDRESS)+2*SIZEOF(WORD), moduleAdr);
					SYSTEM.GET(moduleAdr-2*SIZEOF(ADDRESS), heapBlockAdr);
					ASSERT(heapBlockAdr = linker.moduleBlock.address+2*SIZEOF(ADDRESS));
				#END
				module := SYSTEM.VAL(Modules.Module,moduleAdr);
				module.staticTypeDescs := testTypeDescs; (* trick to identify new object file loaded modules *)
				module.data := arrangement.data.bytes;
				module.code := arrangement.code.bytes;

				module.sb := 0;
				module.body := SYSTEM.VAL(Body, arrangement.bodyAddress);

				(*
				SortProcTable(module);
				SelectionSort(module.exTable);
				*)

				(*
					careful: when GC uses a heuristic for pointer detection on the stack, it will not
					trace the module because the module is not reachable as a heap block in a sweep
					Therefore the code and data array has to be secured in addition.
					Here this is made sure to enter the module in the data structure before returning it.
				*)
				Modules.Initialize(module);
			ELSE module := NIL; res := LinkerError; stringWriter.Update; stringWriter.Get(msg);

			END;
		ELSE
			res := FileNotFound;  COPY(fileName, msg);  Modules.Append(" not found", msg)
		END;
		IF res # Ok THEN module := NIL END;
		IF (res # Ok) & (res # FileNotFound) THEN D.String(msg);D.Ln END;
		RETURN module
	FINALLY
		res := CommandTrapped;
		RETURN NIL
	END LoadObj;

	PROCEDURE Install*;
	VAR extension: ARRAY 32 OF CHAR;
	BEGIN
		Machine.GetConfig("ObjectFileExtension", extension);
		IF extension = "" THEN
			COPY(Machine.DefaultObjectFileExtension, extension)
		END;
		Modules.AddLoader(extension, LoadObj);
	END Install;

	PROCEDURE Remove*;
	VAR extension: ARRAY 32 OF CHAR;
	BEGIN
		Machine.GetConfig("ObjectFileExtension", extension);
		IF extension = "" THEN
			COPY(Machine.DefaultObjectFileExtension, extension)
		END;
		Modules.RemoveLoader(extension,LoadObj);
	END Remove;

	BEGIN
		NEW(testTypeDescs,1);
		Modules.InstallTermHandler(Remove);
		StringPool.GetIndex("@Module",InternalModuleName);
		NEW(moduleList);
		Install;
	END Loader.



	(* concurrent load test:
	VAR
	startConcurrentLoad: BOOLEAN;

	PROCEDURE ConcurrentLoad*;
	VAR i: LONGINT;
		o: OBJECT 		VAR
			mod: Modules.Module; res: WORD; msg: ARRAY 32 OF CHAR;
		BEGIN{ACTIVE}
			WHILE(~startConcurrentLoad) DO END;
			mod := Modules.ThisModule("Test",res,msg);
		END;
	BEGIN
		startConcurrentLoad := FALSE;
		FOR i := 0 TO 128 DO
			NEW(o);
		END;
		startConcurrentLoad := TRUE;
	END ConcurrentLoad;
	*)

