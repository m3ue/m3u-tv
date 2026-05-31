export function showAlert(title: string, message?: string): void {
  window.alert(message ? `${title}\n\n${message}` : title);
}

export function showConfirm(title: string, message: string, onConfirm: () => void): void {
  if (window.confirm(`${title}\n\n${message}`)) {
    onConfirm();
  }
}

export type ChoiceButton = { text: string; onPress?: () => void };

export function showChoiceDialog(
  title: string,
  message: string,
  buttons: ChoiceButton[],
): void {
  const electronAPI = (window as any).electronAPI;
  if (electronAPI?.showMessageBox) {
    const labels = buttons.map((b) => b.text);
    electronAPI
      .showMessageBox({ type: 'question', title, message, buttons: labels, cancelId: labels.length - 1 })
      .then((index: number) => {
        buttons[index]?.onPress?.();
      });
    return;
  }
  // Plain browser fallback: confirm maps first button to OK, last to Cancel
  if (window.confirm(`${title}\n\n${message}`)) {
    buttons[0]?.onPress?.();
  }
}
