#!/usr/bin/perl -w

#
# ACPI-extract.pl (version 0.5) is a Perl script to extract DSDT and SSDT tables from ROM modules.
#
# Version 0.5 - Copyright (c) 2011-2012 by † RevoGirl
# Version 1.2 - Copyright (c) 2013-2014 by Pike R. Alpha <PikeRAlpha@yahoo.com>
#
# The binary files (.aml) will be saved in the AML sub-directory of the current working directory. 
# The IASL compiled/decompiler is called to decompile the files after the AML files are saved.
# Decompiled files will be stored in the DSL directory of the current working directory.
# Now you can change the file(s) you need/want to fix/change.
# Use IASL (or iaslMe) to compile the modified file(s) to check for errors and warnings. 
#
# The next step is to use ACPI-inject.pl (to be developed) to inject the modified file(s).
# Then all you need to do is to repack the BIOS and flash it with the tool of your choice.
#
# Note: The extracted tables are not initialized by the BIOS when we extract them, and thus 
#       they <em>cannot</em> be used as ordinary DSDT and/or SSDT to boot OS X, or any other OS.
#       The reason for this is that certain variables (memory addresses) are not filled in.
#
#
# Usage: [sudo] ./acpiTableExtract.pl
#
# Updates:
#			- v1.2  Renamed script from acpi-extract.pl to acpiTableExtract.pl (Pike, September 2014)
#			-       Signature check expanded, now matches a lot more tables.
#			-       Pushed script to its own Github repository (making it easier to find).
#

#
# Path to IASL.
#
$iasl = "/usr/local/bin/iasl";
                                
sub main()
{
	my $checkedFiles = 0;
	my $skippedFiles = 0;
	my $skippedPaddingFiles = 0;
	
	my @romFiles = glob ("*.ROM");

	foreach my $filename (@romFiles)
	{
		$checkedFiles++;

		# The ACPI header is 36 bytes (skipping anything smaller).
		if ( ((-s $filename) > 36) && (substr($filename, 0, 7) ne "PADDING") )
		{
			if (open(FILE, $filename))
			{
				binmode FILE;

				my $start = 0;
				my $bytesRead = 0;
				my ($data, $patched_data, $targetFile, $signature, $length, $revision, $checksum, $id, $tid, $crev, $cid);

				while (($bytesRead = read(FILE, $signature, 4)) == 4)
				{
					$start += $bytesRead;

					if (#
						# Signatures For Tables Defined By ACPI.
						#
						$signature eq "APIC" || # APIC Description Table.
						$signature eq "MADT" || # Multiple APIC Description Table.
						$signature eq "BERT" || # Boot Error Record Table.
						$signature eq "BGRT" || # Boot Graphics Resource Table.
						$signature eq "CPEP" || # Corrected Platform Error Polling Table.
						$signature eq "DSDT" || # Differentiated System Description Table.
						$signature eq "ECDT" || # Embedded Controller Boot Resources Table.
						$signature eq "EINJ" || # Error Injection Table.
						$signature eq "ERST" || # Error Record Serialization Table.
						$signature eq "FACP" || # Firmware ACPI Control Structure.
						$signature eq "FACS" || # Firmware ACPI Control Structure.
						$signature eq "FPDT" || # Firmware Performance Data Table.
						$signature eq "GTDT" || # Generic Timer Description Table.
						$signature eq "HEST" || # Hardware Error Source Table
						$signature eq "MSCT" || # Maximum System Characteristics Table.
						$signature eq "MPST" || # Memory Power StateTable.
						$signature eq "PMTT" || # Platform Memory Topology Table.
						$signature eq "PSDT" || # Persistent System Description Table.
						$signature eq "RASF" || # CPI RAS FeatureTable
						$signature eq "SBST" || # Smart Battery Table.
						$signature eq "SLIT" || # System Locality Information Table.
						$signature eq "SRAT" || # System Resource Affinity Table.
						$signature eq "SSDT" || # Secondary System Description Table.
						#
						# Signatures For Tables Reserved By ACPI.
						#
						$signature eq "BOOT" || # Simple Boot Flag Table.
						$signature eq "CSRT" || # Core System Resource Table.
						$signature eq "DBGP" || # Debug Port Table.
						$signature eq "DBG2" || # Debug Port Table 2.
						$signature eq "DMAR" || # DMA Remapping Table.
						$signature eq "ETDT" || # Event Timer Description Table (Obsolete).
						$signature eq "HPET" || # High Precision Event Timer Table.
						$signature eq "IBFT" || # SCSI Boot Firmware Table.
						$signature eq "IVRS" || # I/O Virtualization Reporting Structure.
						$signature eq "MCFG" || # PCI Express memory mapped configuration space base address Description Table.
						$signature eq "MCHI" || # Management Controller Host Interface Table.
						$signature eq "MSDM" || # Microsoft Data Management Table.
						$signature eq "SLIC" || # Microsoft Software Licensing Table Specification.
						$signature eq "SPCR" || # Serial Port Console Redirection Table.
						$signature eq "SPMI" || # Server Platform Management Interface Table.
						$signature eq "TCPA" || # Trusted Computing Platform Alliance Capabilities Table.
						$signature eq "TPM2" || # Trusted Platform Module 2 Table.
						$signature eq "UEFI" || # UEFI ACPI Data Table.
						$signature eq "WAET" || # Windows ACPI Eemulated Devices Table.
						$signature eq "WDAT" || # Watch Dog Action Table.
						$signature eq "WDRT" || # Watchdog Resource Table.
						$signature eq "WPBT" || # Windows Platform Binary Table.
						#
						# Miscellaneous ACPI Tables.
						#
						$signature eq "PCCT" )  # Platform Communications Channel Table.
					{
						read(FILE, $length, 4);
						read(FILE, $revision, 1);	# Revision (unused)
						read(FILE, $checksum, 1);	# Checksum (unused)
						read(FILE, $id, 6);			# OEMID
						read(FILE, $tid, 8);		# OEM Table ID
						read(FILE, $crev, 4);		# OEM Revision (unused)
						read(FILE, $cid, 4);		# Creator ID (unused)

						if ($cid eq "AAPL" || $cid eq "INTL" || $id eq "      ")
						{
							printf("%s found in: %s @ 0x%x ", $signature, $filename, $start);
							$length = unpack("N", reverse($length));

							if ($signature eq "FACP" && $length lt 244)
							{
								printf(" - Skipped %s (size error)\n", $signature);
							}
							else
							{
								printf("(%d bytes) ", $length);
								
								if ($id ne "      ")
								{
									printf("'%s' ", $id);
								}

								printf("'%s' ", $tid);

								if ($signature eq "SSDT")
								{
									$targetFile = sprintf("%s-%s.aml", $signature, unpack("A8", $tid));
								}
								else
								{
									$targetFile = sprintf("%s.aml", $signature);
								}

								printf("INTL %s\n", $targetFile);

								seek(FILE, ($start - 4), 0);

								if (($bytesRead = read(FILE, $data, $length)) > 0)
								{
									if (! -d "AML")
									{
										`mkdir AML`
									}

									printf("Saving raw Acpi table data to: AML/$targetFile\n");
									open(OUT, ">AML/$targetFile") || die $!;
									binmode OUT;
									
									# Uninitialized Acpi table data requires some patching
									if ($id eq "      ")
									{
										printf("Patching Acpi table...\n");
										$patched_data = $data;
										# Injecting OEMID (Apple ) and OEM Table ID (Apple00)
										substr($patched_data, 10) = 'APPLE Apple00';
										substr($patched_data, 23) = substr($data, 23, 5);
										# Injecting Creator ID (Loki) and Creator Revision (_) or 0x5f
										substr($patched_data, 28) = 'Loki_';
										substr($patched_data, 33) = substr($data, 33);
										$data = $patched_data;
										printf("%x ", unpack("%A8", $data));
										# Fix checksum here?
									}

									print OUT $data;
									close(OUT);

									if (! -d "DSL")
									{
										`mkdir DSL`
									}

									printf("Decompiling (iasl) Acpi table to: DSL/$targetFile\n");

									`$iasl -p DSL/$targetFile -d AML/$targetFile -e DSL/DSDT.aml,DSL/SSDT*.aml`
								}
							}

							seek(FILE, $start, 0);

							print "\n";
						}

						$signature = "";
						$cid = "";
					}
				}

				close (FILE);
			}
		}
		else
		{
			$skippedFiles++;

			if (substr($filename, 0, 7) eq "PADDING")
			{
				$skippedPaddingFiles++;
			}
		}
	}

	if ($checkedFiles > 0)
	{
		printf("%3d files checked\n%3d files skipped (shorter than Acpi table header)\n%3d file skipped (padding blocks / zero data)\n", $checkedFiles, ($skippedFiles - $skippedPaddingFiles), $skippedPaddingFiles);
	}
	else
	{
		print "Error: No .ROM files found!\n";
	}
}

main();
exit(0);
