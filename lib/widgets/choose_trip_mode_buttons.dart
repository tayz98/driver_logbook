import 'package:driver_logbook/models/trip_category.dart';
import 'package:flutter/material.dart';
import 'package:driver_logbook/utils/help.dart';

class ChooseTripModeButtons extends StatelessWidget {
  final TripCategory initialMode;
  final Function(TripCategory) onModeChanged;

  const ChooseTripModeButtons({
    super.key,
    required this.initialMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    const List<TripCategory> modes = TripCategory.values;
    final selectedIndex = modes.indexOf(initialMode);
    final theme = Theme.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      final buttonWidth = (constraints.maxWidth / modes.length) - 10.0;
      return Row(
        children: [
          const Spacer(),
          ToggleButtons(
            constraints: BoxConstraints.tightFor(
              width: buttonWidth,
              height: 50,
            ),
            isSelected:
                List.generate(modes.length, (index) => index == selectedIndex),
            onPressed: (index) {
              onModeChanged(modes[index]);
            },
            borderRadius: BorderRadius.circular(12.0),
            borderColor: theme.dividerColor,
            selectedBorderColor: theme.colorScheme.primary,
            fillColor: theme.colorScheme.primary.withAlpha(50),
            color: theme.colorScheme.onSurface,
            selectedColor: theme.colorScheme.primary,
            children: modes.map((mode) {
              return SizedBox(
                width: buttonWidth,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 12.0),
                  child: Text(
                    Helper.tripCategoryToDisplay(mode),
                    style: TextStyle(
                      fontSize: 17.0,
                      fontWeight: FontWeight.w600,
                      color: modes[selectedIndex] == mode
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
          ),
          const Spacer(),
        ],
      );
    });
  }
}
