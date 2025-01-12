import 'package:elogbook/models/trip_category.dart';
import 'package:flutter/material.dart';
import 'package:elogbook/utils/help.dart';

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

    return ToggleButtons(
      isSelected:
          List.generate(modes.length, (index) => index == selectedIndex),
      onPressed: (index) {
        onModeChanged(modes[index]);
      },
      borderRadius: BorderRadius.circular(8.0),
      borderColor: Theme.of(context).dividerColor,
      selectedBorderColor: Theme.of(context).colorScheme.primary,
      fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      color: Theme.of(context).colorScheme.onSurface,
      selectedColor: Theme.of(context).colorScheme.primary,
      children: modes.map((mode) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            Helper.tripCategoryToDisplay(mode),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
      }).toList(),
    );
  }
}
