import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';

export interface Recommendation {
  id: string;
  severity: 'strict' | 'moderate' | 'simple' | string;
  title: string;
  description: string;
  suggested_action: string;
  category: string;
}

export interface ExportPdfOptions {
  timetableName: string;
  timetableDescription?: string;
  classes: Array<{ id: string; name: string }>;
  slots: Array<{
    id: string;
    timetable_id: string;
    class_id: string;
    day_of_week: string;
    period_number: number;
    class_subject_id: string | null;
    teacher_id: string | null;
    is_excluded: number | boolean;
  }>;
  dayConfigs: Array<{
    day_of_week: string;
    periods_count: number;
    excluded_periods: string;
  }>;
  subjects: Array<{ id: string; name: string; code?: string }>;
  classSubjects: Array<{ id: string; class_id: string; subject_id: string; tier: number }>;
  teachers: Array<{ id: string; name: string; email?: string; is_absent?: boolean }>;
  recommendations?: Recommendation[];
  targetClassId?: string; // If undefined, exports all classes
  includeLegend?: boolean;
  includeRecommendations?: boolean;
  includeExecutiveSummary?: boolean;
}

const DAY_ORDER: Record<string, number> = {
  Monday: 1,
  Tuesday: 2,
  Wednesday: 3,
  Thursday: 4,
  Friday: 5,
  Saturday: 6,
  Sunday: 7,
};

export function exportTimetableToPdf(options: ExportPdfOptions) {
  const {
    timetableName,
    timetableDescription,
    classes,
    slots,
    dayConfigs,
    subjects,
    classSubjects,
    teachers,
    recommendations = [],
    targetClassId,
    includeLegend = true,
    includeRecommendations = true,
    includeExecutiveSummary = true,
  } = options;

  // Filter target classes
  const targetClasses = targetClassId
    ? classes.filter((c) => c.id === targetClassId)
    : classes;

  if (targetClasses.length === 0) {
    alert('No classes available to export.');
    return;
  }

  // Determine active days in canonical order
  const defaultDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  const activeDays: string[] = (
    dayConfigs && dayConfigs.length > 0
      ? dayConfigs.map((c) => c.day_of_week)
      : defaultDays
  ).sort((a: string, b: string) => (DAY_ORDER[a] || 99) - (DAY_ORDER[b] || 99));

  // Determine max periods
  const maxPeriods =
    dayConfigs && dayConfigs.length > 0
      ? Math.max(...dayConfigs.map((c) => c.periods_count))
      : 8;

  const periodList = Array.from({ length: maxPeriods }, (_, i) => i + 1);

  // Helper lookups
  const getSubject = (csId: string | null) => {
    if (!csId) return null;
    const cs = classSubjects.find((c) => c.id === csId);
    if (!cs) return null;
    return subjects.find((s) => s.id === cs.subject_id) || null;
  };

  const getTeacher = (tId: string | null) => {
    if (!tId) return null;
    return teachers.find((t) => t.id === tId) || null;
  };

  // Initialize jsPDF in Landscape A4 (297mm x 210mm)
  const doc = new jsPDF({
    orientation: 'landscape',
    unit: 'mm',
    format: 'a4',
  });

  const pageWidth = doc.internal.pageSize.getWidth(); // 297mm
  const pageHeight = doc.internal.pageSize.getHeight(); // 210mm
  const marginX = 12;
  const contentWidth = pageWidth - marginX * 2; // 273mm

  const formattedDate = new Date().toLocaleDateString('en-US', {
    weekday: 'short',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });

  let currentPageNumber = 0;
  const totalSheetsCount =
    (targetClasses.length > 1 && includeExecutiveSummary ? 1 : 0) + targetClasses.length;

  // =========================================================================
  // PAGE 1 (OPTIONAL): EXECUTIVE SUMMARY & INSTITUTIONAL DIAGNOSTICS OVERVIEW
  // =========================================================================
  if (targetClasses.length > 1 && includeExecutiveSummary) {
    currentPageNumber++;

    // Header Banner
    doc.setFillColor(15, 23, 42); // Slate-900
    doc.roundedRect(marginX, 10, contentWidth, 20, 2, 2, 'F');

    doc.setTextColor(255, 255, 255);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(14);
    doc.text(`${timetableName.toUpperCase()} — TIMETABLE MASTER REPORT`, marginX + 8, 19);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.setTextColor(203, 213, 225);
    doc.text(
      timetableDescription || 'Institutional Curriculum Allocation & Optimization Audit',
      marginX + 8,
      25
    );

    // Badge
    doc.setFillColor(79, 70, 229); // Indigo-600
    const summaryBadge = 'EXECUTIVE SUMMARY';
    const bWidth = doc.getTextWidth(summaryBadge) + 10;
    doc.roundedRect(pageWidth - marginX - bWidth - 6, 14, bWidth, 12, 1.5, 1.5, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(9);
    doc.text(summaryBadge, pageWidth - marginX - bWidth - 1, 21.5);

    // KPI Metrics Bar
    const filledSlotsCount = slots.filter((s) => s.class_subject_id && !s.is_excluded).length;
    const freeSlotsCount = slots.filter((s) => !s.class_subject_id && !s.is_excluded).length;
    const totalActiveSlots = filledSlotsCount + freeSlotsCount;
    const efficiencyRate =
      totalActiveSlots > 0 ? Math.round((filledSlotsCount / totalActiveSlots) * 100) : 100;

    const kpiBoxes = [
      { label: 'TOTAL COHORTS', value: `${targetClasses.length} Classes`, color: [241, 245, 249] },
      { label: 'ACTIVE TEACHERS', value: `${teachers.length} Faculty`, color: [241, 245, 249] },
      { label: 'ALLOCATED PERIODS', value: `${filledSlotsCount} Periods`, color: [236, 253, 245] },
      { label: 'FREE PERIODS', value: `${freeSlotsCount} Slots`, color: freeSlotsCount > 0 ? [254, 243, 199] : [241, 245, 249] },
      { label: 'SCHEDULE COMPLETION', value: `${efficiencyRate}% Solved`, color: [238, 242, 255] },
    ];

    const kpiWidth = (contentWidth - (kpiBoxes.length - 1) * 3) / kpiBoxes.length;
    kpiBoxes.forEach((kpi, idx) => {
      const kX = marginX + idx * (kpiWidth + 3);
      doc.setFillColor(kpi.color[0], kpi.color[1], kpi.color[2]);
      doc.setDrawColor(226, 232, 240);
      doc.roundedRect(kX, 33, kpiWidth, 16, 1.5, 1.5, 'FD');

      doc.setFont('helvetica', 'bold');
      doc.setFontSize(7);
      doc.setTextColor(100, 116, 139);
      doc.text(kpi.label, kX + kpiWidth / 2, 38.5, { align: 'center' });

      doc.setFont('helvetica', 'bold');
      doc.setFontSize(11);
      doc.setTextColor(15, 23, 42);
      doc.text(kpi.value, kX + kpiWidth / 2, 45, { align: 'center' });
    });

    // Actionable Recommendations Table
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(30, 41, 59);
    doc.text('PRIORITIZED OPTIMIZATION & FREE-PERIOD ELIMINATION STEPS', marginX, 56);

    const recTableHeaders = ['Severity', 'Issue / Diagnostic', 'Context & Impact', 'Recommended Action'];
    const recTableBody =
      recommendations.length > 0
        ? recommendations.map((r) => [
            r.severity === 'strict'
              ? 'CRITICAL DEFICIT'
              : r.severity === 'moderate'
              ? 'BOTTLENECK'
              : 'CAPACITY / TIP',
            r.title,
            r.description,
            r.suggested_action,
          ])
        : [
            [
              'OPTIMAL',
              'Timetable is 100% Complete',
              'All weekly subject targets satisfied with zero free periods.',
              'No manual adjustments required.',
            ],
          ];

    autoTable(doc, {
      startY: 59,
      head: [recTableHeaders],
      body: recTableBody,
      theme: 'grid',
      styles: {
        fontSize: 8,
        cellPadding: 2.8,
        lineColor: [226, 232, 240],
        lineWidth: 0.2,
      },
      headStyles: {
        fillColor: [30, 41, 59],
        textColor: [255, 255, 255],
        fontStyle: 'bold',
        fontSize: 8.5,
      },
      columnStyles: {
        0: { cellWidth: 32, fontStyle: 'bold', halign: 'center' },
        1: { cellWidth: 62, fontStyle: 'bold' },
        2: { cellWidth: 95 },
        3: { cellWidth: 84, fontStyle: 'bold', textColor: [67, 56, 202] },
      },
      margin: { left: marginX, right: marginX },
    });

    // Executive Footer
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(148, 163, 184);
    doc.text(`Executive Overview  |  Page ${currentPageNumber} of ${totalSheetsCount}  |  Generated ${formattedDate}`, marginX, pageHeight - 6);
  }

  // =========================================================================
  // CLASS SHEETS (1 PAGE PER CLASS)
  // =========================================================================
  targetClasses.forEach((cls) => {
    currentPageNumber++;
    if (currentPageNumber > 1) {
      doc.addPage();
    }

    const classSlots = slots.filter((s) => s.class_id === cls.id);
    const offeringsForClass = classSubjects.filter((cs) => cs.class_id === cls.id);

    // --- Header Section ---
    doc.setFillColor(15, 23, 42); // Slate-900
    doc.roundedRect(marginX, 8, contentWidth, 18, 2, 2, 'F');

    // Title
    doc.setTextColor(255, 255, 255);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(12.5);
    doc.text(timetableName.toUpperCase(), marginX + 6, 16);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(203, 213, 225);
    doc.text(
      timetableDescription || 'Official Weekly Curriculum Schedule',
      marginX + 6,
      21.5
    );

    // Class Name Badge (Pill)
    doc.setFillColor(79, 70, 229); // Indigo-600
    const classBadgeText = `CLASS: ${cls.name.toUpperCase()}`;
    const badgeW = doc.getTextWidth(classBadgeText) + 12;
    const badgeX = pageWidth - marginX - badgeW - 4;
    doc.roundedRect(badgeX, 11, badgeW, 12, 1.5, 1.5, 'F');

    doc.setTextColor(255, 255, 255);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(10);
    doc.text(classBadgeText, badgeX + 6, 19);

    // Meta sub-strip
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(100, 116, 139);
    doc.text(`Generated: ${formattedDate} • Curriculum Allocation Matrix`, marginX + 1, 29.5);

    // --- Build Table Rows & Columns for autoTable ---
    const tableHeaders = [
      'Slot',
      ...activeDays.map((day) => {
        const cfg = dayConfigs.find((c) => c.day_of_week === day);
        return cfg ? `${day.toUpperCase()}\n(${cfg.periods_count} Periods)` : day.toUpperCase();
      }),
    ];

    const tableBody: any[][] = [];

    periodList.forEach((period) => {
      const row: any[] = [`Period ${period}`];

      activeDays.forEach((day) => {
        const cfg = dayConfigs.find((c) => c.day_of_week === day);
        const dayLimit = cfg ? cfg.periods_count : 8;

        if (period > dayLimit) {
          row.push({
            content: '—\nNo Session',
            styles: {
              fillColor: [248, 250, 252],
              textColor: [148, 163, 184],
              fontStyle: 'italic',
            },
          });
          return;
        }

        const slot = classSlots.find(
          (s) => s.day_of_week === day && s.period_number === period
        );

        if (slot && (slot.is_excluded === 1 || slot.is_excluded === true)) {
          row.push({
            content: 'EXCLUDED\n[Reserved Slot]',
            styles: {
              fillColor: [254, 243, 199], // Amber-100
              textColor: [146, 64, 14], // Amber-800
              fontStyle: 'bold',
            },
          });
          return;
        }

        if (!slot || !slot.class_subject_id) {
          row.push({
            content: '— Free Period —',
            styles: {
              fillColor: [255, 255, 255],
              textColor: [148, 163, 184],
              fontStyle: 'italic',
            },
          });
          return;
        }

        const subject = getSubject(slot.class_subject_id);
        const teacher = getTeacher(slot.teacher_id);
        const subjectName = subject ? subject.name : 'Unknown Subject';
        const teacherName = teacher ? teacher.name : 'Unassigned';

        row.push({
          content: `${subjectName}\n[${teacherName}]`,
          styles: {
            fillColor: [240, 249, 255], // Sky-50
            textColor: [15, 23, 42], // Slate-900
            fontStyle: 'bold',
          },
        });
      });

      tableBody.push(row);
    });

    // Render Main Grid Table
    autoTable(doc, {
      startY: 32,
      head: [tableHeaders],
      body: tableBody,
      theme: 'grid',
      styles: {
        fontSize: 8.5,
        cellPadding: 2.2,
        halign: 'center',
        valign: 'middle',
        lineColor: [203, 213, 225],
        lineWidth: 0.2,
      },
      headStyles: {
        fillColor: [30, 41, 59],
        textColor: [255, 255, 255],
        fontSize: 8.5,
        fontStyle: 'bold',
        halign: 'center',
        valign: 'middle',
      },
      columnStyles: {
        0: {
          cellWidth: 24,
          fontStyle: 'bold',
          fillColor: [241, 245, 249],
          textColor: [51, 65, 85],
          fontSize: 8,
        },
      },
      margin: { left: marginX, right: marginX },
    });

    const lastTableY = (doc as any).lastAutoTable?.finalY || 135;

    // --- Bottom Information Section ---
    const bottomCardY = lastTableY + 3.5;
    const availableBottomHeight = pageHeight - bottomCardY - 8;

    if (availableBottomHeight >= 18) {
      const cardHeight = Math.min(availableBottomHeight, 30);

      if (includeRecommendations) {
        // MODE A: DIAGNOSTIC & OPTIMIZATION REPORT (Side-by-Side Dual Cards)
        const cardGap = 4;
        const leftCardWidth = (contentWidth - cardGap) * 0.48;
        const rightCardWidth = (contentWidth - cardGap) * 0.52;

        // LEFT CARD: CURRICULUM SUBJECTS & ALLOCATED TARGETS
        doc.setFillColor(248, 250, 252);
        doc.setDrawColor(226, 232, 240);
        doc.roundedRect(marginX, bottomCardY, leftCardWidth, cardHeight, 1.5, 1.5, 'FD');

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(7.5);
        doc.setTextColor(51, 65, 85);
        doc.text('CURRICULUM BREAKDOWN & TARGETS:', marginX + 4, bottomCardY + 4.5);

        doc.setFont('helvetica', 'normal');
        doc.setFontSize(7);
        doc.setTextColor(100, 116, 139);

        const legendItems = offeringsForClass.map((cs) => {
          const sub = subjects.find((s) => s.id === cs.subject_id);
          const name = sub ? sub.name : 'Unknown';
          const targetStr = cs.tier === 3 ? '3x/wk' : '1x/wk';
          return `${name} (${targetStr})`;
        });

        let curLine = '';
        let lineOffset = 0;
        legendItems.forEach((item) => {
          const testLine = curLine ? `${curLine}  •  ${item}` : item;
          if (doc.getTextWidth(testLine) > leftCardWidth - 10) {
            doc.text(curLine, marginX + 4, bottomCardY + 9 + lineOffset);
            curLine = item;
            lineOffset += 3.8;
          } else {
            curLine = testLine;
          }
        });
        if (curLine && lineOffset <= cardHeight - 12) {
          doc.text(curLine, marginX + 4, bottomCardY + 9 + lineOffset);
        }

        // RIGHT CARD: ACTIONABLE CLASS RECOMMENDATIONS & DEFICITS
        const rightCardX = marginX + leftCardWidth + cardGap;
        const classRecs = recommendations.filter(
          (r) =>
            r.title.toLowerCase().includes(cls.name.toLowerCase()) ||
            r.description.toLowerCase().includes(cls.name.toLowerCase())
        );

        doc.setFillColor(248, 250, 252);
        doc.setDrawColor(226, 232, 240);
        doc.roundedRect(rightCardX, bottomCardY, rightCardWidth, cardHeight, 1.5, 1.5, 'FD');

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(7.5);
        doc.setTextColor(51, 65, 85);
        doc.text('CLASS DIAGNOSTICS & OPTIMIZATION:', rightCardX + 4, bottomCardY + 4.5);

        if (classRecs.length > 0) {
          let recOffset = 0;
          classRecs.slice(0, 2).forEach((rec) => {
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(7);
            doc.setTextColor(rec.severity === 'strict' ? 185 : 180, 28, 28);
            doc.text(`• ${rec.title}`, rightCardX + 4, bottomCardY + 9 + recOffset);

            doc.setFont('helvetica', 'normal');
            doc.setFontSize(6.5);
            doc.setTextColor(71, 85, 105);
            const actionText = `Action: ${rec.suggested_action}`;
            const splitAction = doc.splitTextToSize(actionText, rightCardWidth - 10);
            doc.text(splitAction, rightCardX + 6, bottomCardY + 12.5 + recOffset);

            recOffset += 10.5;
          });
        } else {
          doc.setFont('helvetica', 'bold');
          doc.setFontSize(7.5);
          doc.setTextColor(22, 101, 52); // Emerald-800
          doc.text('✓ All weekly subject targets satisfied with complete coverage.', rightCardX + 4, bottomCardY + 11);

          doc.setFont('helvetica', 'normal');
          doc.setFontSize(7);
          doc.setTextColor(100, 116, 139);
          doc.text('No scheduling deficits or teacher clashes detected for this cohort.', rightCardX + 4, bottomCardY + 16);
        }
      } else if (includeLegend) {
        // MODE B: ORDINARY / CLEAN TIMETABLE (Full-Width Clean Legend Box)
        doc.setFillColor(248, 250, 252);
        doc.setDrawColor(226, 232, 240);
        doc.roundedRect(marginX, bottomCardY, contentWidth, cardHeight, 1.5, 1.5, 'FD');

        doc.setFont('helvetica', 'bold');
        doc.setFontSize(8);
        doc.setTextColor(30, 41, 59);
        doc.text('OFFICIAL CURRICULUM & SUBJECT DIRECTORY:', marginX + 5, bottomCardY + 5.5);

        doc.setFont('helvetica', 'normal');
        doc.setFontSize(7.5);
        doc.setTextColor(71, 85, 105);

        const legendItems = offeringsForClass.map((cs) => {
          const sub = subjects.find((s) => s.id === cs.subject_id);
          const name = sub ? sub.name : 'Unknown';
          const targetStr = cs.tier === 3 ? 'Core (3x/wk)' : 'Standard (1x/wk)';
          return `${name} [${targetStr}]`;
        });

        let curLine = '';
        let lineOffset = 0;
        legendItems.forEach((item) => {
          const testLine = curLine ? `${curLine}   •   ${item}` : item;
          if (doc.getTextWidth(testLine) > contentWidth - 14) {
            doc.text(curLine, marginX + 5, bottomCardY + 11 + lineOffset);
            curLine = item;
            lineOffset += 4.5;
          } else {
            curLine = testLine;
          }
        });
        if (curLine && lineOffset <= cardHeight - 12) {
          doc.text(curLine, marginX + 5, bottomCardY + 11 + lineOffset);
        }
      }
    }

    // --- Footer ---
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(148, 163, 184);
    doc.text(
      `Sheet ${currentPageNumber} of ${totalSheetsCount}  |  Class: ${cls.name}  |  ${timetableName}`,
      marginX,
      pageHeight - 4.5
    );
    doc.text(
      `Generated by Automated Timetable Matrix Engine`,
      pageWidth - marginX - doc.getTextWidth(`Generated by Automated Timetable Matrix Engine`),
      pageHeight - 4.5
    );
  });

  // Filename
  const sanitizedTtName = timetableName.replace(/[^a-zA-Z0-9_-]/g, '_');
  const modePrefix = includeRecommendations ? 'Diagnostic_Report' : 'Classroom_Timetable';
  let filename = '';
  if (targetClassId && targetClasses.length === 1) {
    const sanitizedClassName = targetClasses[0].name.replace(/[^a-zA-Z0-9_-]/g, '_');
    filename = `${modePrefix}_${sanitizedClassName}_${sanitizedTtName}.pdf`;
  } else {
    filename = `${modePrefix}_All_Classes_${sanitizedTtName}.pdf`;
  }

  doc.save(filename);
}
