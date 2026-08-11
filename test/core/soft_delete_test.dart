import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/constants/soft_delete.dart';

void main() {
  test('el prefijo es el que ya vive en las bases instaladas', () {
    // No puede cambiar: hay filas marcadas asi en dispositivos en produccion
    // y el backend recibe el nombre tal cual (I2/I3).
    expect(SoftDelete.prefix, '[DEL]-');
  });

  test('marcar dos veces no encadena prefijos', () {
    // Con la interpolacion suelta que habia antes en 4 sitios, borrar dos
    // veces la misma sede producia '[DEL]-[DEL]-Gimnasio', y entonces el
    // filtro seguia ocultandola pero el nombre ya estaba corrupto en el
    // backend.
    final once = SoftDelete.mark('Gimnasio Municipal');
    expect(once, '[DEL]-Gimnasio Municipal');
    expect(SoftDelete.mark(once), once);
  });

  test('isDeleted distingue marcada de no marcada', () {
    expect(SoftDelete.isDeleted('[DEL]-Gimnasio'), isTrue);
    expect(SoftDelete.isDeleted('Gimnasio'), isFalse);
    expect(
      SoftDelete.isDeleted('Gimnasio [DEL]-'),
      isFalse,
      reason: 'el prefijo es prefijo, no aparece a mitad del nombre',
    );
  });
}
