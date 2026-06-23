# Design engine — Korean localization glossary (DRAFT for review)

Edit the **Korean** column. Leave the **English** column alone (it's the lookup key reference).
Notes:
- `CMYK` / `Hex` / `RGB` and units `pt` / `mm` stay as-is.
- For **select options**, the stored value (left of `→`) stays English; only the shown label (Korean) changes.
- `%{...}` placeholders must stay intact.

---

## Properties Panel (Layout / Typography / Header-Footer tabs)

| English | Korean (edit me) |
|---|---|
| Layout | 레이아웃 |
| Typography | 단락정의 |
| Header/Footer | 머리말·꼬리말 |
| Design Properties | 디자인 속성 |
| Heading Lines | 제목박스 높이 (본문 줄 수) |
| Heading V-Align | 제목 세로 정렬 |
| Body Line Count | 본문 줄 수 |
| Columns | 단 수 |
| Gutter (pt) | 단 간격 (pt) |
| TOC Text V-Align | 차례 글자 세로 정렬 |
| Heading Elements | 제목 요소 |
| + Add | + 추가 |
| Add Style | 스타일 추가 |
| Heading Background | 제목 배경 |
| Color | 색상 |
| Image | 이미지 |
| Gradient | 그라데이션 |
| Angle (degrees) | 각도 (도) |
| Start | 시작 |
| End | 끝 |
| Background Color | 배경 색상 |
| Page Background (Bleed) | 페이지 배경 (재단 여백) |
| Extends 3mm beyond trim for bleed. Leave blank for no background. | 재단선 바깥 3mm까지 확장됩니다. 배경을 없애려면 비워 두세요. |
| Text Box Position | 텍스트 상자 위치 |
| Anchor Position | 기준 위치 |
| Default (Bottom Left) | 기본값 (왼쪽 아래) |
| Grid Width | 그리드 너비 |
| Grid Height | 그리드 높이 |
| Document Cover | 문서 표지 |
| Cover Type | 표지 유형 |
| Header | 머리말 |
| Footer | 꼬리말 |
| Content | 내용 |
| Y-offset (mm) | 세로 오프셋 (mm) |
| Show on first page | 첫 페이지에 표시 |
| Name | 이름 |
| Edit | 편집 |
| Save | 저장 |
| Current: %{filename} | 현재: %{filename} |

## Paragraph-style Fields

| English | Korean (edit me) |
|---|---|
| Identity | 기본 정보 |
| Name | 이름 |
| Korean Name | 한글 이름 |
| Font | 글꼴 |
| Size (pt) | 크기 (pt) |
| Scale | 장평 |
| Text | 텍스트 |
| Color | 색상 |
| Align | 정렬 |
| Tracking | 자간 |
| Space Width | 어간|
| Line Spacing | 행간 |
| Bold & Emphasis | 굵게·강조 |
| Bold Font | 굵은 글꼴 |
| Bold Color | 굵은 글자 색상 |
| Emphasis Font | 강조 글꼴 |
| Emphasis Color | 강조 색상 |
| Spacing | 간격 |
| First Line Indent | 첫 줄 들여쓰기 |
| Left Indent | 왼쪽 들여쓰기 |
| Right Indent | 오른쪽 들여쓰기 |
| Space Before (pt) | 문단 위 간격 (pt) |
| Space After (pt) | 문단 아래 간격 (pt) |
| Space Before (lines) | 문단 위 간격 (줄) |
| Space After (lines) | 문단 아래 간격 (줄) |
| Fill | 채우기 |
| Fill Type | 채우기 유형 |
| Fill Color | 채우기 색상 |
| Ending Color | 끝 색상 |
| Gradient Dir. | 그라데이션 방향 |
| Border | 테두리 |
| Thickness (pt) | 두께 (pt) |
| Border Color | 테두리 색상 |
| Border Sides | 테두리 면 |
| Top | 위 |
| Bottom | 아래 |
| Left | 왼쪽 |
| Right | 오른쪽 |
| Rounded Corners | 둥근 모서리 |
| Corner Radius | 모서리 반경 |
| Padding | 안쪽 여백 |
| Padding Top (pt) | 위쪽 여백 (pt) |
| Padding Bottom (pt) | 아래쪽 여백 (pt) |

## Paragraph-style Panel / Form

| English | Korean (edit me) |
|---|---|
| ← Back | ← 뒤로 |
| New Style | 새 스타일 |
| Please fix the following errors: | 다음 오류를 수정해 주세요: |
| Save | 저장 |
| Cancel | 취소 |
| Revert to base | 기본값으로 되돌리기 |

## Standalone Editor (gem Edit) + Preview

| English | Korean (edit me) |
|---|---|
| Preview | 미리보기 |
| Loading preview… | 미리보기 불러오는 중… |
| Preview generation failed | 미리보기 생성 실패 |
| Base Text Styles (inherited from theme) | 기본 텍스트 스타일 (테마에서 상속) |
| Document Styles (overrides) | 문서 스타일 (재정의) |
| Edit → | 편집 → |
| These styles are shared across all doc types. Edit them on the | 이 스타일은 모든 문서 유형에서 공유됩니다. 다음에서 편집하세요: |

## Paper-size Editor

| English | Korean (edit me) |
|---|---|
| Binding Margin (mm) | 제본 여백 (mm) |
| Body Line Count | 본문 줄 수 |
| TOC Page Count | 차례 페이지 수 |
| Top | 위 |
| Bottom | 아래 |
| Left | 왼쪽 |
| Right | 오른쪽 |

## Select option labels (value stays English, only label changes)

| attr | value → Korean label |
|---|---|
| heading_v_align / toc_v_align | center → 가운데 · top → 위 · bottom → 아래 |
| heading background type | color → 색상 · image → 이미지 · gradient → 그라데이션 |
| text align | left → 왼쪽 · center → 가운데 · right → 오른쪽 · justify → 양쪽 |
| fill type | none → 없음 · solid → 단색 · gradient → 그라데이션 |
| gradient direction | horizontal → 가로 · vertical → 세로 · diagonal → 대각선 |
| corner radius | none → 없음 · small → 작게 · medium → 보통 · large → 크게 |

## Added in spec review (please check these too)

Preview overlay labels (shown over the live preview on hover) + fallback:

| English | Korean (edit me) |
|---|---|
| Title (overlay) | 제목 |
| Subtitle (overlay) | 부제 |
| Author (overlay) | 지은이 |
| Publisher (overlay) | 펴낸곳 |
| Heading (overlay fallback) | 제목 |
| Body (overlay fallback) | 본문 |
| TOC Entry (overlay) | 차례 항목 |
| Generating preview... | 미리보기 생성 중… |

Properties Panel — missed strings:

| English | Korean (edit me) |
|---|---|
| Has Document Cover | 문서 표지 사용 |
| Header Left | 머리말 왼쪽 |
| Header Right | 머리말 오른쪽 |
| Footer Left | 꼬리말 왼쪽 |
| Footer Right | 꼬리말 오른쪽 |

Paper-size editor — missed strings:

| English | Korean (edit me) |
|---|---|
| Margins (mm) | 여백 (mm) |
| Base Text Styles | 기본 텍스트 스타일 |

Standalone editor — missed string:

| English | Korean (edit me) |
|---|---|
| theme page (link text) | 테마 페이지 |

**Left literal (not translated, by design):** `(base)` badge, `IDX` hidden template placeholder, ` › ` breadcrumb separator, `CMYK`/`Hex`/`RGB`, `pt`/`mm`, and `(%{korean_name})` interpolations.
