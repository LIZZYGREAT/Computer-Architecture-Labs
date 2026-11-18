# Unsupported TLB Exceptions

## Scope

Lab15 precise TLB exception handling is not implemented in this revision. The CPU does not claim to raise and retire MIPS `TLBL`, `TLBS`, or `Modified` exceptions for mapped-page translation failures. These cases are `UNSUPPORTED_BY_SCOPE`, not functional PASS cases.

## Observed translation behavior

`addr_translate` marks a mapped address valid only when the TLB lookup matches, the selected page is valid, and—on a store—the page is dirty. An invalid translation produces `paddr=0`; it does not fall back to using the virtual address as a physical address. The Lab14 translation test records these component-level cases:

- `tlb_miss_blocks_translation_without_va_fallback`
- `invalid_page_blocks_translation`
- `clean_page_blocks_store`

The 11/11 Lab14 translation result proves address-translation gating. It does not prove end-to-end precise exception state, BadVAddr/Context/EntryHi updates, EPC/BD handling, vectoring, or resumed execution.

## Cache-maintenance boundary

The project’s Lab19 convention allows Index operations `{00, 08, 01, 09}` to select the cache set/way from the virtual address without a TLB mapping. Hit operations require a valid physical translation. For an untranslated Hit operation, the top blocks both cache requests and completion; the directed marker is `IDX-03_UNSUPPORTED_BY_SCOPE`. This is an explicit unsupported boundary, not a TLB exception.

## Expected behavior and limits

In Lab19, instruction and data cache requests and address-accept signals are gated by their respective `translation_valid` results. The translation-unit tests verify that a miss, invalid page, or clean-page store fails translation. The full CPU test added for this revision covers an untranslated CACHE Hit operation, not a regular mapped load/store page-fault retirement sequence. Therefore this revision does not claim a complete end-to-end no-bus/no-commit exception test for those three cases.

Because Lab15 exception retirement is absent, the full CPU may remain waiting at the affected fetch or memory operation. No finite exception completion is claimed by this document. The expected safety behavior is that an invalid translation is not accepted by ICache/DCache and no store retires; verifying that behavior together with precise exception state remains follow-up work if Lab15 is required.

When Lab15 is required, implement and verify precise `TLBL`, `TLBS`, and `Modified` handling as a separate change. That work must cover CP0 BadVAddr/Context/EntryHi updates, EPC and BD, exception priority and vectoring, and retry after software repairs the mapping.
